import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { copyFile, mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync, spawnSync } from "node:child_process";
import test from "node:test";

const repoRoot = fileURLToPath(new URL("..", import.meta.url));
const digest = createHash("sha256").update("detect-secrets work-packet fixture").digest("hex");
const nonDigest = createHash("sha256").update("detect-secrets non-digest fixture").digest("hex");

async function scan(files, baseline) {
  execFileSync(
    "detect-secrets",
    ["scan", "--baseline", baseline, "--all-files", ...files],
    {
      cwd: repoRoot,
      encoding: "utf8",
      env: { ...process.env, PYTHONDONTWRITEBYTECODE: "1" },
    },
  );
  return JSON.parse(await readFile(baseline, "utf8")).results;
}

function hookScan(files, baseline) {
  return spawnSync("detect-secrets-hook", ["--baseline", baseline, ...files], {
    cwd: repoRoot,
    encoding: "utf8",
    env: { ...process.env, PYTHONDONTWRITEBYTECODE: "1" },
  });
}

test("detect-secrets filters only canonical Purpose work-packet digests", async () => {
  const lefthook = await readFile(join(repoRoot, "lefthook.yml"), "utf8");
  assert.match(
    lefthook,
    /run: PYTHONDONTWRITEBYTECODE=1 detect-secrets-hook --baseline \.secrets\.baseline \{staged_files\}/,
    "the staged hook must not leave Python bytecode in the task workspace",
  );

  const packetDir = await mkdtemp(join(repoRoot, "docs", "work", ".detect-secrets-packet-"));
  const duplicatePacketDir = await mkdtemp(join(repoRoot, "docs", "work", ".detect-secrets-packet-"));
  const baselineDir = await mkdtemp(join(tmpdir(), "detect-secrets-baseline-"));
  const baseline = join(baselineDir, ".secrets.baseline");
  const hookBaseline = join(baselineDir, ".hook-secrets.baseline");
  await Promise.all([
    copyFile(join(repoRoot, ".secrets.baseline"), baseline),
    copyFile(join(repoRoot, ".secrets.baseline"), hookBaseline),
  ]);
  await mkdir(packetDir, { recursive: true });

  const files = {
    allowed: join(packetDir, "purpose.contract.json"),
    repeatedCanonical: join(packetDir, "work.spec.json"),
    duplicatePermittedValue: join(duplicatePacketDir, "purpose.contract.json"),
    wrongField: join(packetDir, "evidence.bundle.json"),
    entropy: join(packetDir, "evidence.bundle.json"),
    wrongName: join(packetDir, "README.json"),
  };
  await Promise.all([
    writeFile(
      files.allowed,
      JSON.stringify({ digest: { algorithm: "sha256", canonicalization: "raw-bytes", value: digest } }),
    ),
    writeFile(
      files.repeatedCanonical,
      JSON.stringify({
        purpose_subject_digest: {
          algorithm: "sha256",
          canonicalization: "engine-json-v1",
          value: digest,
        },
        workspec_subject_digest: {
          algorithm: "sha256",
          canonicalization: "engine-json-v1",
          value: digest,
        },
      }),
    ),
    writeFile(
      files.duplicatePermittedValue,
      JSON.stringify({
        digest: { algorithm: "sha256", canonicalization: "raw-bytes", value: digest },
        actual_token: digest,
      }),
    ),
    writeFile(
      files.wrongField,
      JSON.stringify({
        digest: { algorithm: "sha512", canonicalization: "raw-bytes", value: digest },
        uppercase: digest.toUpperCase(),
      }),
    ),
    writeFile(files.entropy, JSON.stringify({ token: nonDigest })),
    writeFile(
      files.wrongName,
      JSON.stringify({ digest: { algorithm: "sha256", canonicalization: "raw-bytes", value: digest } }),
    ),
  ]);

  try {
    const results = await scan(Object.values(files), baseline);
    assert.equal(results[relative(repoRoot, files.allowed)], undefined, "canonical digest must be filtered");
    assert.equal(
      results[relative(repoRoot, files.repeatedCanonical)],
      undefined,
      "repeated canonical digest fields must be filtered",
    );
    assert.ok(
      results[relative(repoRoot, files.duplicatePermittedValue)]?.length,
      "a duplicated permitted digest value must remain detectable as an actual token",
    );
    assert.ok(
      results[relative(repoRoot, files.wrongField)]?.length >= 2,
      "wrong digest structure and uppercase value must remain detectable",
    );
    for (const filename of [files.entropy, files.wrongName]) {
      assert.ok(results[relative(repoRoot, filename)]?.length, `${filename} must remain detectable`);
    }

    const allowedHook = hookScan([files.allowed], hookBaseline);
    assert.equal(allowedHook.status, 0, allowedHook.stderr || allowedHook.stdout);

    const repeatedCanonicalHook = hookScan([files.repeatedCanonical], hookBaseline);
    assert.equal(repeatedCanonicalHook.status, 0, repeatedCanonicalHook.stderr || repeatedCanonicalHook.stdout);

    const duplicateHook = hookScan([files.duplicatePermittedValue], hookBaseline);
    assert.equal(duplicateHook.status, 1, "the staged hook must reject a duplicated digest value");
  } finally {
    await rm(packetDir, { recursive: true, force: true });
    await rm(duplicatePacketDir, { recursive: true, force: true });
    await rm(baselineDir, { recursive: true, force: true });
  }
});
