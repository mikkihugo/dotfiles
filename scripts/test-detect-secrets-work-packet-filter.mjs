import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { copyFile, mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync, spawnSync } from "node:child_process";
import test from "node:test";

const repoRoot = fileURLToPath(new URL("..", import.meta.url));
const digest = createHash("sha256").update("detect-secrets work-packet fixture").digest("hex");
const nonDigest = createHash("sha256").update("detect-secrets non-digest fixture").digest("hex");
const revision = createHash("sha256").update("detect-secrets work-packet revision fixture").digest("hex").slice(0, 40);
const otherRevision = createHash("sha256").update("detect-secrets unrelated revision fixture").digest("hex").slice(0, 40);

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
  const gitBin = process.env.SE_GIT_BIN;
  assert.ok(gitBin?.startsWith("/"), "fixture requires the Nix-pinned SE_GIT_BIN");
  return spawnSync("detect-secrets-hook", ["--baseline", baseline, ...files], {
    cwd: repoRoot,
    encoding: "utf8",
    // detect-secrets-hook internally runs `git diff` to check its copied
    // baseline. Keep that upstream subprocess inside the fixture's pinned
    // Git path instead of inheriting the agent-facing refusal shim.
    env: {
      ...process.env,
      PATH: `${dirname(gitBin)}:${process.env.PATH}`,
      PYTHONDONTWRITEBYTECODE: "1",
    },
  });
}

test("detect-secrets filters only canonical Purpose work-packet metadata", async () => {
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
    duplicateDigestKey: join(duplicatePacketDir, "work.spec.json"),
    wrongField: join(packetDir, "evidence.bundle.json"),
    entropy: join(packetDir, "evidence-entropy.json"),
    wrongName: join(packetDir, "README.json"),
    snapshotRevision: join(packetDir, "current-spec.snapshot.json"),
    proofRevision: join(packetDir, "evidence", "red-proof.json"),
    fixtureProofRevision: join(packetDir, "evidence", "red-fixture-proof.json"),
    greenProofRevision: join(packetDir, "evidence", "green-proof.json"),
    greenFixtureProofRevision: join(packetDir, "evidence", "green-fixture-proof.json"),
    duplicateRevision: join(packetDir, "evidence", "green-duplicate-proof.json"),
    duplicateKeyRevision: join(packetDir, "evidence", "green-duplicate-key-proof.json"),
    nestedRevision: join(packetDir, "evidence", "green-nested-proof.json"),
    malformedRevision: join(packetDir, "evidence", "red-malformed-proof.json"),
    unrelatedRevision: join(packetDir, "evidence", "red-unrelated-proof.json"),
    wrongRevisionName: join(packetDir, "evidence", "README.json"),
  };
  assert.equal(
    new Set(Object.values(files)).size,
    Object.keys(files).length,
    "each fixture must use a distinct path",
  );
  await mkdir(dirname(files.proofRevision), { recursive: true });
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
      files.duplicateDigestKey,
      `{"digest":{"algorithm":"sha256","canonicalization":"raw-bytes","value":"${digest}","actual_token":"${digest}"},"digest":{"algorithm":"sha256","canonicalization":"raw-bytes","value":"${digest}"}}`,
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
    writeFile(
      files.snapshotRevision,
      JSON.stringify({
        schema_version: "current-spec-snapshot/v1",
        source: { uri: "repository://fixture", revision },
      }),
    ),
    writeFile(
      files.proofRevision,
      JSON.stringify({
        schema_version: "fixture-red-proof/v1",
        source: { path: "fixture", revision, role: "baseline" },
      }),
    ),
    writeFile(
      files.fixtureProofRevision,
      JSON.stringify({
        schema_version: "fixture-red-fixture-proof/v1",
        source: { path: "fixture", revision, role: "baseline" },
      }),
    ),
    writeFile(
      files.greenProofRevision,
      JSON.stringify({
        schema_version: "fixture-green-proof/v1",
        source: { path: "fixture", revision, role: "baseline" },
      }),
    ),
    writeFile(
      files.greenFixtureProofRevision,
      JSON.stringify({
        schema_version: "fixture-green-fixture-proof/v1",
        source: { path: "fixture", revision, role: "baseline" },
      }),
    ),
    writeFile(
      files.duplicateRevision,
      JSON.stringify({
        source: { path: "fixture", revision, role: "baseline" },
        actual_token: revision,
      }),
    ),
    writeFile(
      files.duplicateKeyRevision,
      `{"source":{"path":"fixture","revision":"${revision}","role":"baseline","actual_token":"${revision}"},"source":{"path":"fixture","revision":"${revision}","role":"baseline"}}`,
    ),
    writeFile(
      files.nestedRevision,
      JSON.stringify({
        metadata: { source: { path: "fixture", revision, role: "baseline" } },
      }),
    ),
    writeFile(
      files.malformedRevision,
      JSON.stringify({ source: { path: "fixture", revision } }),
    ),
    writeFile(
      files.unrelatedRevision,
      JSON.stringify({
        source: { path: "fixture", revision, role: "baseline" },
        actual_token: otherRevision,
      }),
    ),
    writeFile(
      files.wrongRevisionName,
      JSON.stringify({ source: { path: "fixture", revision, role: "baseline" } }),
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
    assert.equal(
      results[relative(repoRoot, files.snapshotRevision)],
      undefined,
      "a canonical current-spec source revision must be filtered",
    );
    assert.equal(
      results[relative(repoRoot, files.proofRevision)],
      undefined,
      "a canonical red/green proof source revision must be filtered",
    );
    assert.equal(
      results[relative(repoRoot, files.fixtureProofRevision)],
      undefined,
      "a canonical red-fixture proof source revision must be filtered",
    );
    assert.equal(
      results[relative(repoRoot, files.greenProofRevision)],
      undefined,
      "a canonical green proof source revision must be filtered",
    );
    assert.equal(
      results[relative(repoRoot, files.greenFixtureProofRevision)],
      undefined,
      "a canonical green-fixture proof source revision must be filtered",
    );
    assert.ok(
      results[relative(repoRoot, files.duplicatePermittedValue)]?.length,
      "a duplicated permitted digest value must remain detectable as an actual token",
    );
    assert.ok(
      results[relative(repoRoot, files.wrongField)]?.length >= 2,
      "wrong digest structure and uppercase value must remain detectable",
    );
    for (const filename of [
      files.entropy,
      files.wrongName,
      files.duplicateDigestKey,
      files.duplicateRevision,
      files.duplicateKeyRevision,
      files.nestedRevision,
      files.malformedRevision,
      files.unrelatedRevision,
      files.wrongRevisionName,
    ]) {
      assert.ok(results[relative(repoRoot, filename)]?.length, `${filename} must remain detectable`);
    }

    const allowedHook = hookScan([files.allowed], hookBaseline);
    assert.equal(allowedHook.status, 0, allowedHook.stderr || allowedHook.stdout);

    const repeatedCanonicalHook = hookScan([files.repeatedCanonical], hookBaseline);
    assert.equal(repeatedCanonicalHook.status, 0, repeatedCanonicalHook.stderr || repeatedCanonicalHook.stdout);

    const snapshotRevisionHook = hookScan([files.snapshotRevision], hookBaseline);
    assert.equal(snapshotRevisionHook.status, 0, snapshotRevisionHook.stderr || snapshotRevisionHook.stdout);

    const proofRevisionHook = hookScan([files.proofRevision], hookBaseline);
    assert.equal(proofRevisionHook.status, 0, proofRevisionHook.stderr || proofRevisionHook.stdout);

    const fixtureProofRevisionHook = hookScan([files.fixtureProofRevision], hookBaseline);
    assert.equal(fixtureProofRevisionHook.status, 0, fixtureProofRevisionHook.stderr || fixtureProofRevisionHook.stdout);

    const greenProofRevisionHook = hookScan([files.greenProofRevision], hookBaseline);
    assert.equal(greenProofRevisionHook.status, 0, greenProofRevisionHook.stderr || greenProofRevisionHook.stdout);

    const greenFixtureProofRevisionHook = hookScan([files.greenFixtureProofRevision], hookBaseline);
    assert.equal(greenFixtureProofRevisionHook.status, 0, greenFixtureProofRevisionHook.stderr || greenFixtureProofRevisionHook.stdout);

    const duplicateHook = hookScan([files.duplicatePermittedValue], hookBaseline);
    assert.equal(duplicateHook.status, 1, "the staged hook must reject a duplicated digest value");

    const duplicateDigestKeyHook = hookScan([files.duplicateDigestKey], hookBaseline);
    assert.equal(duplicateDigestKeyHook.status, 1, "the staged hook must reject duplicate digest keys");

    const duplicateRevisionHook = hookScan([files.duplicateRevision], hookBaseline);
    assert.equal(duplicateRevisionHook.status, 1, "the staged hook must reject a duplicated source revision");

    const duplicateKeyRevisionHook = hookScan([files.duplicateKeyRevision], hookBaseline);
    assert.equal(duplicateKeyRevisionHook.status, 1, "the staged hook must reject duplicate JSON object keys");

    const unrelatedRevisionHook = hookScan([files.unrelatedRevision], hookBaseline);
    assert.equal(unrelatedRevisionHook.status, 1, "the staged hook must reject an unrelated source-file token");
  } finally {
    await rm(packetDir, { recursive: true, force: true });
    await rm(duplicatePacketDir, { recursive: true, force: true });
    await rm(baselineDir, { recursive: true, force: true });
  }
});
