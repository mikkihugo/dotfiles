#!/usr/bin/env node
// sync-model-context.mjs — refresh max_context_size in the kimi-code catalog
// (~/.kimi-code/config.toml) from each provider's live model listing.
//
//   - ollama-cloud  -> native POST /api/show, read <family>.context_length
//   - other openai  -> GET /v1/models, read context_length / top_provider.context_length
//   - anthropic / google / kimi -> skipped (no uniform listing of limits)
//
// OUTPUT caps are intentionally NOT synced: the enforced per-endpoint output
// limit is not published anywhere (ollama-cloud rejects max_tokens it does not
// advertise), so runner clamps output to a conservative CEILING.
//
// Dry-run by default; pass --write to apply. Line-based edits preserve TOML
// comments/formatting.

import { readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const CONFIG =
	process.env.KIMI_CODE_CONFIG || join(homedir(), ".kimi-code/config.toml");
const WRITE = process.argv.includes("--write");

const lines = readFileSync(CONFIG, "utf8").split("\n");

// ── parse [providers.<name>] (type / base_url / api_key) ────────────────────
const providers = {};
{
	let cur = null;
	for (const l of lines) {
		const h = l.match(/^\[providers\.("?)([^"\]]+)\1\]/);
		if (h) {
			cur = h[2];
			providers[cur] = {};
			continue;
		}
		if (/^\[/.test(l)) {
			cur = null;
			continue;
		}
		if (!cur) continue;
		const t = l.match(/^\s*type\s*=\s*"([^"]+)"/);
		if (t) providers[cur].type = t[1];
		const b = l.match(/^\s*base_url\s*=\s*"([^"]+)"/);
		if (b) providers[cur].base = b[1];
		const k = l.match(/^\s*api_key\s*=\s*"([^"]*)"/);
		if (k) providers[cur].key = k[1];
	}
}

// ── parse [models."<provider>/<model>"] entries + the max_context_size line ──
const entries = [];
{
	let cur = null;
	for (let i = 0; i < lines.length; i++) {
		const h = lines[i].match(/^\[models\."([^"]+)"\]/);
		if (h) {
			cur = {
				label: h[1],
				provider: h[1].split("/")[0],
				model: h[1].slice(h[1].indexOf("/") + 1),
				ctxLine: -1,
				ctx: null,
			};
			entries.push(cur);
			continue;
		}
		if (/^\[/.test(lines[i])) {
			cur = null;
			continue;
		}
		if (!cur) continue;
		const mm = lines[i].match(/^\s*model\s*=\s*"([^"]+)"/);
		if (mm) cur.model = mm[1];
		const c = lines[i].match(/^\s*max_context_size\s*=\s*(\d+)/);
		if (c) {
			cur.ctxLine = i;
			cur.ctx = Number(c[1]);
		}
	}
}

const TIMEOUT_MS = 20000;
async function jget(url, opts = {}) {
	const ac = new AbortController();
	const t = setTimeout(() => ac.abort(), TIMEOUT_MS);
	try {
		const r = await fetch(url, { ...opts, signal: ac.signal });
		if (!r.ok) return null;
		return await r.json();
	} catch {
		return null;
	} finally {
		clearTimeout(t);
	}
}

async function ollamaContext(base, key, model) {
	const root = base.replace(/\/v1\/?$/, "");
	const j = await jget(`${root}/api/show`, {
		method: "POST",
		headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
		body: JSON.stringify({ model }),
	});
	const mi = j?.model_info || {};
	for (const [k, v] of Object.entries(mi))
		if (/\.context_length$/.test(k) && typeof v === "number") return v;
	return null;
}

const listCache = new Map();
async function openaiContext(base, key, model) {
	if (!listCache.has(base)) {
		const j = await jget(`${base.replace(/\/$/, "")}/models`, {
			headers: { Authorization: `Bearer ${key}` },
		});
		listCache.set(base, j?.data || []);
	}
	const m = listCache
		.get(base)
		.find((x) => x.id === model || x.id?.endsWith(`/${model}`));
	if (!m) return null;
	return (
		m.context_length ||
		m.top_provider?.context_length ||
		m.max_context_length ||
		null
	);
}

const changes = [];
const skipped = [];
for (const e of entries) {
	const p = providers[e.provider];
	if (!p?.key || !e.model || e.ctxLine < 0) {
		skipped.push(`${e.label} (no provider/key/ctx line)`);
		continue;
	}
	let ctx = null;
	if (p.type === "openai" && /ollama/.test(p.base || ""))
		ctx = await ollamaContext(p.base, p.key, e.model);
	else if (p.type === "openai") ctx = await openaiContext(p.base, p.key, e.model);
	else {
		skipped.push(`${e.label} (type=${p.type})`);
		continue;
	}
	if (ctx && ctx !== e.ctx) changes.push({ ...e, to: ctx });
}

for (const c of changes)
	console.log(`${c.label.padEnd(44)} max_context_size ${c.ctx} -> ${c.to}`);
console.log(
	`\n${changes.length} context update(s) ${WRITE ? "APPLIED" : "(dry-run; pass --write to apply)"}; ${skipped.length} skipped (non-openai / no listing).`,
);

if (WRITE && changes.length) {
	for (const c of changes)
		lines[c.ctxLine] = lines[c.ctxLine].replace(
			/(\bmax_context_size\s*=\s*)\d+/,
			`$1${c.to}`,
		);
	writeFileSync(CONFIG, lines.join("\n"));
	console.log("written to", CONFIG);
}
