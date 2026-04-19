import os, sys, subprocess, email, email.policy, psycopg2, logging, re
from email.utils import parsedate_to_datetime

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger(__name__)

USER = os.environ["MAIL_USER"]
MAILBOX = os.environ.get("MAILBOX", "INBOX")
DB_URL = os.environ["DB_URL"]
DOVECOT_CONTAINER = os.environ.get("DOVECOT_CONTAINER", "mailcowdockerized-dovecot-mailcow-1")
ACCOUNT = USER


def search_uids():
    r = subprocess.run(
        ["docker", "exec", DOVECOT_CONTAINER, "doveadm", "search", "-u", USER, "mailbox", MAILBOX, "all"],
        capture_output=True, text=True, timeout=120,
    )
    uids = []
    for line in r.stdout.splitlines():
        parts = line.strip().split()
        if len(parts) >= 2:
            uids.append(parts[1])
    return uids


def fetch_raw(uid):
    r = subprocess.run(
        ["docker", "exec", DOVECOT_CONTAINER, "doveadm", "fetch", "-u", USER, "text", "mailbox", MAILBOX, "uid", str(uid)],
        capture_output=True, timeout=60,
    )
    out = r.stdout
    if not out:
        return None
    txt_start = out.find(b"text:")
    if txt_start == -1:
        return None
    body = out[txt_start + 6:]
    return body.rstrip(b"\x0c\n")


def coerce_str(x):
    if isinstance(x, bytes):
        return x.decode("utf-8", errors="replace")
    return x or ""


uids = search_uids()
log.info("found %d messages", len(uids))
conn = psycopg2.connect(DB_URL)
cur = conn.cursor()

inserted = skipped = errors = 0
for i, uid in enumerate(uids):
    raw = fetch_raw(uid)
    if not raw:
        errors += 1
        continue
    try:
        msg = email.message_from_bytes(raw, policy=email.policy.default)
    except Exception:
        errors += 1
        continue
    message_id = coerce_str(msg.get("Message-Id") or msg.get("Message-ID") or f"dovecot-{USER}-{uid}").strip()
    subject = coerce_str(msg.get("Subject")).replace("\x00", "")
    sender = coerce_str(msg.get("From")).replace("\x00", "")
    recipients = coerce_str(msg.get("To")).replace("\x00", "")
    try:
        date_sent = parsedate_to_datetime(msg.get("Date")) if msg.get("Date") else None
    except Exception:
        date_sent = None
    body = ""
    try:
        if msg.is_multipart():
            for part in msg.walk():
                if part.get_content_type() == "text/plain" and part.get_content_disposition() != "attachment":
                    body = part.get_content()
                    break
            if not body:
                for part in msg.walk():
                    if part.get_content_type() == "text/html":
                        body = part.get_content()
                        break
        else:
            body = msg.get_content()
    except Exception:
        body = raw
    body = coerce_str(body).replace("\x00", "")[:32000]
    try:
        cur.execute(
            """
            INSERT INTO gmail_messages (message_id, subject, sender, recipients, date_sent, body, account)
            VALUES (%s,%s,%s,%s,%s,%s,%s)
            ON CONFLICT (message_id, account) DO NOTHING
            """,
            (message_id[:512], subject, sender, recipients, date_sent, body, ACCOUNT),
        )
        rc = cur.rowcount
        inserted += rc
        if rc == 0:
            skipped += 1
    except Exception as e:
        log.warning("insert fail uid=%s: %s", uid, e)
        conn.rollback()
        errors += 1
        continue
    if (i + 1) % 200 == 0:
        conn.commit()
        log.info("progress %d/%d inserted=%d skipped=%d errors=%d", i + 1, len(uids), inserted, skipped, errors)
conn.commit()
log.info("DONE: total=%d inserted=%d skipped=%d errors=%d", len(uids), inserted, skipped, errors)
