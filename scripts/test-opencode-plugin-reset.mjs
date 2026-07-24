import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { access, readFile } from "node:fs/promises";
import test from "node:test";

const PROVIDER_BASELINE_SHA256 =
  "7badedb7f071f9e1440901fbe5cfb6b3af06f46182edd27904967d999a8549e3";
const THIRD_PARTY_PLUGINS = [
  "envsitter-guard",
  "opencode-mem",
  "oh-my-opencode",
  "oh-my-openagent",
];
const OVERLAY_FILES = [
  "config/opencode/oh-my-opencode.json",
  "config/opencode/opencode-mem.jsonc",
];

const stable = (value) =>
  Array.isArray(value)
    ? value.map(stable)
    : value && typeof value === "object"
      ? Object.fromEntries(
          Object.keys(value)
            .sort()
            .map((key) => [key, stable(value[key])]),
        )
      : value;

const exists = async (path) => {
  try {
    await access(path);
    return true;
  } catch {
    return false;
  }
};

test("managed opencode.json activates no third-party plugin", async () => {
  const config = JSON.parse(await readFile("config/opencode/opencode.json", "utf8"));
  const plugins = Array.isArray(config.plugin) ? config.plugin : [];
  const offenders = plugins.filter((entry) =>
    THIRD_PARTY_PLUGINS.some((name) => String(entry).includes(name)),
  );
  assert.deepEqual(
    offenders,
    [],
    `third-party plugin activations remain: ${offenders.join(", ")}`,
  );
});

test("plugin overlay config files and profile links are absent", async () => {
  for (const path of OVERLAY_FILES) {
    assert.equal(await exists(path), false, `${path} must be deleted`);
  }
  const links = JSON.parse(await readFile("profiles/default/links.json", "utf8"));
  const overlayLinks = Object.entries(links.links ?? {}).filter(
    ([target, source]) =>
      OVERLAY_FILES.includes(source) ||
      OVERLAY_FILES.some((path) => target.endsWith(path.split("/").pop())),
  );
  assert.deepEqual(
    overlayLinks,
    [],
    `overlay links remain: ${overlayLinks.map(([target]) => target).join(", ")}`,
  );
});

test("provider subtree remains the observed baseline", async () => {
  const config = JSON.parse(await readFile("config/opencode/opencode.json", "utf8"));
  const digest = createHash("sha256")
    .update(JSON.stringify(stable(config.provider), null, 2) + "\n")
    .digest("hex");
  assert.equal(
    digest,
    PROVIDER_BASELINE_SHA256,
    "provider subtree drifted from the observed baseline",
  );
});
