// deepseek-tool-parser.mjs — defensive fallback for DeepSeek-V3 inline tool calls.
//
// Some OpenAI-compatible backends (notably ollama-cloud serving DeepSeek-base
// models like cogito-2.1:671b) intermittently FAIL to structure the model's
// tool call: instead of emitting `tool_calls`, they leak DeepSeek's raw token
// format into the assistant `content`:
//
//   <|tool▁calls▁begin|><|tool▁call▁begin|>function<|tool▁sep|>NAME
//   ```json
//   { ...args... }
//   ```<|tool▁call▁end|>  …repeat…  <|tool▁calls▁end|>
//
// (bars are ASCII U+007C, separators are U+2581). ollama's server-side parser
// catches this only ~1/4 of the time at the model's settings and ~0/4 at
// temperature 0 — which the review runner uses — so cogito narrates instead of
// acting. This wrapper parses those tokens client-side and emits real tool calls
// ONLY when the turn produced no structured tool call AND the begin-token is
// present, so it is a no-op for every well-behaved provider/model.

const SUB = "▁"; // ▁ U+2581
const BEGIN = "<|tool" + SUB + "calls" + SUB + "begin|>";
const FENCE = String.fromCharCode(96, 96, 96); // ``` (kept out of any String.raw context)

// <|tool▁call▁begin|>[function]<|tool▁sep|>NAME ```[json] {ARGS} ```
const CALL_RE = new RegExp(
  "<\\|tool" + SUB + "call" + SUB + "begin\\|>\\s*(?:function)?\\s*<\\|tool" + SUB + "sep\\|>\\s*([A-Za-z0-9_.\\-]+)\\s*" +
    FENCE + "(?:json)?\\s*([\\s\\S]*?)" + FENCE,
  "g",
);

/**
 * Parse DeepSeek-V3 inline tool-call tokens from assistant content.
 * Returns [{ name, arguments }] where `arguments` is a validated JSON string.
 * Calls whose argument block is not valid JSON are skipped.
 */
export function parseDeepSeekToolCalls(text) {
  if (typeof text !== "string" || !text.includes(BEGIN)) return [];
  const calls = [];
  CALL_RE.lastIndex = 0;
  let m;
  while ((m = CALL_RE.exec(text)) !== null) {
    const name = (m[1] || "").trim();
    const argsRaw = (m[2] || "").trim();
    if (!name) continue;
    try {
      JSON.parse(argsRaw);
    } catch {
      continue; // skip malformed argument blocks rather than emit a bad call
    }
    calls.push({ name, arguments: argsRaw });
  }
  return calls;
}

function newId() {
  try {
    return globalThis.crypto.randomUUID();
  } catch {
    return "ds-" + Math.random().toString(16).slice(2);
  }
}

/**
 * Wrap a kosong ChatProvider so its streamed message yields synthetic `function`
 * parts parsed from DeepSeek inline tokens when the backend failed to structure
 * the call. Pass-through (zero behavior change) for everything else.
 */
export function wrapWithDeepSeekToolFallback(provider) {
  if (!provider || typeof provider.generate !== "function") return provider;
  const origGenerate = provider.generate.bind(provider);
  provider.generate = async function (...args) {
    const sm = await origGenerate(...args);
    return wrapStreamedMessage(sm);
  };
  return provider;
}

function wrapStreamedMessage(sm) {
  async function* iterate() {
    let sawTool = false;
    let suppressing = false; // true once the begin-token is seen — drop the rest of content
    let held = ""; // holdback buffer (covers a marker split across deltas)
    let full = ""; // full accumulated content, for end-of-stream parsing
    const HOLD = BEGIN.length - 1;
    for await (const part of sm) {
      if (part && (part.type === "function" || part.type === "tool_call_part")) {
        sawTool = true;
        yield part;
        continue;
      }
      if (part && part.type === "text" && typeof part.text === "string") {
        full += part.text;
        if (suppressing) continue; // inside the token block: strip it from visible content
        held += part.text;
        const idx = held.indexOf(BEGIN);
        if (idx >= 0) {
          const out = held.slice(0, idx);
          suppressing = true;
          held = "";
          if (out) yield { type: "text", text: out };
          continue;
        }
        if (held.length > HOLD) {
          yield { type: "text", text: held.slice(0, held.length - HOLD) };
          held = held.slice(held.length - HOLD);
        }
        continue;
      }
      yield part;
    }
    if (!suppressing && held) yield { type: "text", text: held };
    if (sawTool) return;
    for (const call of parseDeepSeekToolCalls(full)) {
      yield { type: "function", id: newId(), name: call.name, arguments: call.arguments };
    }
  }
  // Proxy so finishReason/usage/id getters stay live (read after iteration),
  // overriding only the async iterator.
  return new Proxy(sm, {
    get(target, prop, receiver) {
      if (prop === Symbol.asyncIterator) return () => iterate();
      const v = Reflect.get(target, prop, receiver);
      return typeof v === "function" ? v.bind(target) : v;
    },
  });
}
