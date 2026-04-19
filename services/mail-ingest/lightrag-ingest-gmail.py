import os, sys, time, json, logging, psycopg2, psycopg2.extras, requests

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger(__name__)

DB_URL = os.environ["DB_URL"]
LIGHTRAG_URL = os.environ.get("LIGHTRAG_URL", "http://lightrag:9621")
LIGHTRAG_API_KEY = os.environ["LIGHTRAG_API_KEY"]

STATE_FILE = "/app/data/ingest-state.json"
try:
    state = json.load(open(STATE_FILE))
except Exception:
    state = {"done_ids": []}
done = set(state["done_ids"])
log.info("previously ingested: %d", len(done))

sess = requests.Session()
sess.headers.update({"X-API-Key": LIGHTRAG_API_KEY, "Content-Type": "application/json"})

while True:
    conn = psycopg2.connect(DB_URL)
    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute("SELECT id, account, subject, sender, date_sent, body FROM gmail_messages ORDER BY id")
        rows = cur.fetchall()
    conn.close()
    to_do = [r for r in rows if r["id"] not in done]
    log.info("total=%d pending=%d", len(rows), len(to_do))
    if not to_do:
        log.info("nothing to ingest, sleeping 5min")
        time.sleep(300)
        continue
    for row in to_do:
        text = f"Account: {row['account']}\nFrom: {row['sender'] or ''}\nSubject: {row['subject'] or '(no subject)'}\nDate: {row['date_sent']}\n\n{(row['body'] or '')[:8000]}"
        payload = {"text": text, "file_source": f"mail/{row['account']}/{row['id']}"}
        for attempt in range(10):
            try:
                r = sess.post(f"{LIGHTRAG_URL}/documents/text", json=payload, timeout=120)
                if r.status_code == 200:
                    break
                if r.status_code == 429:
                    log.warning("rate limited, sleep 30s")
                    time.sleep(30)
                    continue
                log.error("POST %d: %s", r.status_code, r.text[:200])
                time.sleep(10)
            except Exception as e:
                log.error("req err: %s", e)
                time.sleep(10)
        else:
            log.error("giving up id=%s", row["id"])
            continue
        done.add(row["id"])
        if len(done) % 10 == 0:
            state["done_ids"] = list(done)
            json.dump(state, open(STATE_FILE, "w"))
            log.info("progress %d ingested", len(done))
    state["done_ids"] = list(done)
    json.dump(state, open(STATE_FILE, "w"))