#!/usr/bin/env node
// probe-model-output.mjs — empirically discover each model's ENFORCED output cap.
//
// The per-endpoint output limit (the max_tokens a provider accepts) is not
// published in any listing — ollama-cloud rejects max_tokens it never advertises.
// So probe it: per (provider, model) send a tiny completion with a descending
// ladder of candidate max_tokens and return the HIGHEST the endpoint accepts.
// The model only emits a few tokens ("hi") — max_tokens is validated server-side
// BEFORE generation, so each probe is one cheap call.
//
// Usage:
//   node probe-model-output.mjs                 # probe configured Kimi model aliases
//   node probe-model-output.mjs ollama-cloud/deepseek-v4-pro [more…]
//   node probe-model-output.mjs --write         # store result as max_output_size
//
// Only openai-type providers are probed (anthropic/google use other wire shapes).

import { readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const CONFIG =
	process.env.KIMI_CODE_CONFIG || join(homedir(), ".kimi-code/config.toml");
const WRITE = process.argv.includes("--write");
const argModels = process.argv.slice(2).filter((a) => !a.startsWith("--"));

const lines = readFileSync(CONFIG, "utf8").split("\n");

// providers
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

// model entries (label -> {model, max_output_size line})
const entries = new Map();
{
	let cur = null;
	for (let i = 0; i < lines.length; i++) {
		const h = lines[i].match(/^\[models\."([^"]+)"\]/);
		if (h) {
			cur = { label: h[1], model: h[1].slice(h[1].indexOf("/") + 1), outLine: -1, out: null };
			entries.set(h[1], cur);
			continue;
		}
		if (/^\[/.test(lines[i])) {
			cur = null;
			continue;
		}
		if (!cur) continue;
		const mm = lines[i].match(/^\s*model\s*=\s*"([^"]+)"/);
		if (mm) cur.model = mm[1];
		const o = lines[i].match(/^\s*max_output_size\s*=\s*(\d+)/);
		if (o) {
			cur.outLine = i;
			cur.out = Number(o[1]);
		}
	}
}

let targets = argModels;
if (!targets.length) {
	targets = [...entries.keys()];
}

const LADDER = [262144, 131072, 65536, 32768, 16384, 8192];
const TIMEOUT_MS = 30000;

async function probe(base, key, model) {
	for (const cap of LADDER) {
		const ac = new AbortController();
		const t = setTimeout(() => ac.abort(), TIMEOUT_MS);
		let r;
		try {
			r = await fetch(`${base.replace(/\/$/, "")}/chat/completions`, {
				method: "POST",
				headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
				body: JSON.stringify({
					model,
					messages: [{ role: "user", content: "hi" }],
					max_tokens: cap,
				}),
				signal: ac.signal,
			});
		} catch (e) {
			clearTimeout(t);
			return { error: `network: ${String(e).slice(0, 60)}` };
		}
		clearTimeout(t);
		if (r.ok) return { cap };
		const body = await r.text().catch(() => "");
		// a max_tokens / output-limit rejection → too high, drop to next rung
		if (
			r.status === 400 &&
			/max_tokens|max_completion|max_output|output|exceed|limit|too large|maximum/i.test(body)
		)
			continue;
		// auth / model-missing / balance / rate → can't determine the cap
		return { error: `${r.status}: ${body.replace(/\s+/g, " ").slice(0, 90)}` };
	}
	return { error: "rejected at every rung (< 8192?)" };
}

const results = [];
for (const label of targets) {
	const provider = label.split("/")[0];
	const model = label.slice(label.indexOf("/") + 1);
	const p = providers[provider];
	if (!p?.key) {
		console.log(`${label.padEnd(44)} SKIP (no provider/key)`);
		continue;
	}
	if (p.type && p.type !== "openai") {
		console.log(`${label.padEnd(44)} SKIP (type=${p.type})`);
		continue;
	}
	const res = await probe(p.base, p.key, model);
	const e = entries.get(label);
	if (res.cap) {
		const cur = e?.out ?? "?";
		console.log(
			`${label.padEnd(44)} enforced max_tokens = ${res.cap}  (catalog: ${cur})`,
		);
		if (e && res.cap !== e.out) results.push({ ...e, to: res.cap });
	} else {
		console.log(`${label.padEnd(44)} ${res.error}`);
	}
}

console.log(
	`\n${results.length} catalog max_output_size correction(s) ${WRITE ? "APPLIED" : "(dry-run; pass --write)"}.`,
);
if (WRITE && results.length) {
	for (const r of results)
		if (r.outLine >= 0)
			lines[r.outLine] = lines[r.outLine].replace(
				/(\bmax_output_size\s*=\s*)\d+/,
				`$1${r.to}`,
			);
	writeFileSync(CONFIG, lines.join("\n"));
	console.log("written to", CONFIG);
}
