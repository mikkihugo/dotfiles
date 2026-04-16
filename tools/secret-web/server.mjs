import cors from "cors";
import express from "express";
import yaml from "js-yaml";
import { mkdtemp, readdir, readFile, rm, writeFile, rename } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";

const DEFAULT_API_PORT = 4310;
const DOTFILES_ROOT = process.env.DOTFILES_ROOT ?? path.join(process.env.HOME ?? "", ".dotfiles");
const SECRETS_DIRECTORY = path.join(DOTFILES_ROOT, "secrets");
const SHARED_SECRETS_FILE = path.join(SECRETS_DIRECTORY, "shared.yaml");
const SOPS_COMMAND = process.env.SOPS_COMMAND ?? "sops";
const SOPS_AGE_KEY_FILE =
  process.env.SOPS_AGE_KEY_FILE ?? path.join(process.env.HOME ?? "", ".config/sops/age/keys.txt");
const app = express();

function runCommand(command, args, extraEnvironment = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      env: {
        ...process.env,
        SOPS_AGE_KEY_FILE,
        ...extraEnvironment
      }
    });
    let stdout = "";
    let stderr = "";

    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString();
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });
    child.on("error", (error) => {
      reject(error);
    });
    child.on("close", (code) => {
      if (code === 0) {
        resolve({ stdout, stderr });
        return;
      }
      reject(new Error(stderr || `Command failed with exit code ${code}`));
    });
  });
}

function assertStringMap(data, fileName) {
  if (typeof data !== "object" || data === null || Array.isArray(data)) {
    throw new Error(`${fileName} must decrypt to a top-level mapping`);
  }
  for (const [key, value] of Object.entries(data)) {
    if (typeof value !== "string") {
      throw new Error(`${fileName} contains non-string value for ${key}`);
    }
  }
  return data;
}

async function decryptSecretFile(filePath) {
  const { stdout } = await runCommand(SOPS_COMMAND, ["-d", filePath]);
  const data = yaml.load(stdout);
  return assertStringMap(data, path.basename(filePath));
}

async function encryptAndReplaceYaml(filePath, plainTextYaml) {
  const temporaryDirectory = await mkdtemp(path.join(tmpdir(), "secret-web-"));
  const temporaryFilePath = path.join(temporaryDirectory, `${path.basename(filePath)}.tmp`);

  try {
    await writeFile(temporaryFilePath, plainTextYaml, "utf8");
    await runCommand(SOPS_COMMAND, ["-e", "-i", temporaryFilePath]);
    await rename(temporaryFilePath, filePath);
  } finally {
    await rm(temporaryDirectory, { recursive: true, force: true });
  }
}

app.use(cors());
app.use(express.json({ limit: "1mb" }));

app.get("/api/files", async (_request, response) => {
  try {
    const directoryEntries = await readdir(SECRETS_DIRECTORY, { withFileTypes: true });
    const fileNames = directoryEntries
      .filter((entry) => entry.isFile() && (entry.name.endsWith(".yaml") || entry.name.endsWith(".yml")))
      .map((entry) => entry.name)
      .sort((leftName, rightName) => leftName.localeCompare(rightName));

    response.json({ files: fileNames, sharedFile: path.basename(SHARED_SECRETS_FILE) });
  } catch (error) {
    response.status(500).json({ error: error instanceof Error ? error.message : "Failed to list secret files" });
  }
});

app.get("/api/files/:fileName", async (request, response) => {
  try {
    const fileName = path.basename(request.params.fileName);
    const filePath = path.join(SECRETS_DIRECTORY, fileName);
    const secretsByKey = await decryptSecretFile(filePath);
    const secrets = Object.entries(secretsByKey)
      .map(([key, value]) => ({
        key,
        value,
        length: value.length
      }))
      .sort((left, right) => left.key.localeCompare(right.key));

    response.json({ fileName, secrets });
  } catch (error) {
    response.status(500).json({ error: error instanceof Error ? error.message : "Failed to read secret file" });
  }
});

app.post("/api/files/:fileName/secret", async (request, response) => {
  try {
    const fileName = path.basename(request.params.fileName);
    const filePath = path.join(SECRETS_DIRECTORY, fileName);
    const { key, value } = request.body ?? {};

    if (typeof key !== "string" || key.length === 0) {
      response.status(400).json({ error: "Missing secret key" });
      return;
    }

    if (typeof value !== "string") {
      response.status(400).json({ error: "Missing secret value" });
      return;
    }

    const secretsByKey = await decryptSecretFile(filePath);
    secretsByKey[key] = value;
    const nextYaml = yaml.dump(secretsByKey, {
      lineWidth: 120,
      noRefs: true,
      sortKeys: true
    });

    await encryptAndReplaceYaml(filePath, nextYaml);
    response.json({ ok: true });
  } catch (error) {
    response.status(500).json({ error: error instanceof Error ? error.message : "Failed to save secret" });
  }
});

app.get("/api/shared", async (_request, response) => {
  try {
    const secretsByKey = await decryptSecretFile(SHARED_SECRETS_FILE);
    response.json({ fileName: path.basename(SHARED_SECRETS_FILE), keys: Object.keys(secretsByKey).sort() });
  } catch (error) {
    response.status(500).json({ error: error instanceof Error ? error.message : "Failed to read shared secrets" });
  }
});

app.listen(DEFAULT_API_PORT, "127.0.0.1", () => {
  console.log(`secret-web API listening on http://127.0.0.1:${DEFAULT_API_PORT}`);
});
