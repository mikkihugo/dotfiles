import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { fileURLToPath } from "node:url";

const repoRoot = fileURLToPath(new URL("..", import.meta.url));

const liveEndpoint = /(?:https?:\/\/|git@|ssh:\/\/git@)[^\s"'`]*infra\.centralcloud\.com/;
const liveHostName = /^\s*HostName\s+\S*infra\.centralcloud\.com\b/m;
const liveBao = /BAO_ADDR=.*infra\.centralcloud\.com/;
const liveCluster = /cluster\.infra\.centralcloud\.com/;

function liveHits(stdout) {
  return stdout
    .split("\n")
    .filter(Boolean)
    .filter((line) => {
      const text = line.replace(/^[^:]+:\d+:/, "");
      if (liveEndpoint.test(text)) return true;
      if (liveHostName.test(text)) return true;
      if (liveBao.test(text)) return true;
      if (liveCluster.test(text)) return true;
      return false;
    });
}

test("live config does not call retired *.infra.centralcloud.com endpoints", () => {
  const result = spawnSync(
    "rg",
    [
      "-n",
      "--glob",
      "!archive/**",
      "--glob",
      "!.git/**",
      "infra\\.centralcloud\\.com",
      ".",
    ],
    { cwd: repoRoot, encoding: "utf8" },
  );
  assert.notEqual(result.status, 2, result.stderr);
  const hits = liveHits(result.stdout ?? "");
  assert.deepEqual(hits, [], hits.join("\n"));
});
