import { useEffect, useMemo, useState } from "react";

type SecretFileListResponse = {
  files: string[];
  sharedFile: string;
};

type SecretRecord = {
  key: string;
  value: string;
  length: number;
};

type SecretFileResponse = {
  fileName: string;
  secrets: SecretRecord[];
};

const SHARED_FILE_NAME = "shared.yaml";

function maskSecretValue(secretValue: string): string {
  if (secretValue.length <= 8) {
    return "•".repeat(secretValue.length);
  }
  return `${secretValue.slice(0, 3)}${"•".repeat(Math.max(secretValue.length - 6, 4))}${secretValue.slice(-3)}`;
}

async function readJson<T>(url: string, init?: RequestInit): Promise<T> {
  const response = await fetch(url, init);
  if (!response.ok) {
    const responseBody = (await response.json().catch(() => null)) as { error?: string } | null;
    throw new Error(responseBody?.error ?? `Request failed: ${response.status}`);
  }
  return (await response.json()) as T;
}

export function App() {
  const [fileNames, setFileNames] = useState<string[]>([]);
  const [selectedFileName, setSelectedFileName] = useState<string>(SHARED_FILE_NAME);
  const [secretRecords, setSecretRecords] = useState<SecretRecord[]>([]);
  const [activeSecretKey, setActiveSecretKey] = useState<string | null>(null);
  const [editingSecretValue, setEditingSecretValue] = useState("");
  const [revealedSecretKeys, setRevealedSecretKeys] = useState<Record<string, boolean>>({});
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [statusMessage, setStatusMessage] = useState<string>("Loading secrets…");
  const [isBusy, setIsBusy] = useState<boolean>(true);

  useEffect(() => {
    void (async () => {
      try {
        const data = await readJson<SecretFileListResponse>("/api/files");
        setFileNames(data.files);
        setSelectedFileName(data.files.includes(SHARED_FILE_NAME) ? SHARED_FILE_NAME : data.files[0] ?? "");
        setErrorMessage(null);
      } catch (error) {
        setErrorMessage(error instanceof Error ? error.message : "Failed to load file list");
      }
    })();
  }, []);

  useEffect(() => {
    if (!selectedFileName) {
      return;
    }

    setIsBusy(true);
    void (async () => {
      try {
        const data = await readJson<SecretFileResponse>(`/api/files/${encodeURIComponent(selectedFileName)}`);
        setSecretRecords(data.secrets);
        setActiveSecretKey(data.secrets[0]?.key ?? null);
        setEditingSecretValue(data.secrets[0]?.value ?? "");
        setStatusMessage(`Loaded ${data.secrets.length} secrets from ${data.fileName}`);
        setErrorMessage(null);
      } catch (error) {
        setErrorMessage(error instanceof Error ? error.message : "Failed to load secrets");
      } finally {
        setIsBusy(false);
      }
    })();
  }, [selectedFileName]);

  const activeSecretRecord = useMemo(
    () => secretRecords.find((secretRecord) => secretRecord.key === activeSecretKey) ?? null,
    [activeSecretKey, secretRecords]
  );

  useEffect(() => {
    if (activeSecretRecord) {
      setEditingSecretValue(activeSecretRecord.value);
    }
  }, [activeSecretRecord]);

  async function saveSecretValue() {
    if (!activeSecretRecord) {
      return;
    }

    setIsBusy(true);
    try {
      await readJson<{ ok: boolean }>(`/api/files/${encodeURIComponent(selectedFileName)}/secret`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json"
        },
        body: JSON.stringify({
          key: activeSecretRecord.key,
          value: editingSecretValue
        })
      });

      const refreshedSecrets = await readJson<SecretFileResponse>(`/api/files/${encodeURIComponent(selectedFileName)}`);
      setSecretRecords(refreshedSecrets.secrets);
      setStatusMessage(`Saved ${activeSecretRecord.key} to ${selectedFileName}`);
      setErrorMessage(null);
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : "Failed to save secret");
    } finally {
      setIsBusy(false);
    }
  }

  async function copySecretValue(secretValue: string) {
    await navigator.clipboard.writeText(secretValue);
    setStatusMessage("Copied secret to clipboard");
  }

  function toggleSecretReveal(secretKey: string) {
    setRevealedSecretKeys((previousRevealState) => ({
      ...previousRevealState,
      [secretKey]: !previousRevealState[secretKey]
    }));
  }

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="sidebar-header">
          <div>
            <p className="eyebrow">SOPS</p>
            <h1>Secrets</h1>
          </div>
          <p className="sidebar-copy">Local editor for every YAML file in <code>~/.dotfiles/secrets</code>.</p>
        </div>
        <div className="file-list">
          {fileNames.map((fileName) => (
            <button
              key={fileName}
              className={`file-card${fileName === selectedFileName ? " is-selected" : ""}`}
              onClick={() => setSelectedFileName(fileName)}
              type="button"
            >
              <span>{fileName}</span>
              {fileName === SHARED_FILE_NAME ? <span className="pill">source of truth</span> : null}
            </button>
          ))}
        </div>
      </aside>

      <main className="main-panel">
        <header className="panel-header">
          <div>
            <p className="eyebrow">Active file</p>
            <h2>{selectedFileName || "No file selected"}</h2>
          </div>
          <div className="status-stack">
            <span className={`status-pill${isBusy ? " is-busy" : ""}`}>{statusMessage}</span>
            {errorMessage ? <span className="status-pill is-error">{errorMessage}</span> : null}
          </div>
        </header>

        <section className="content-grid">
          <div className="secret-list">
            {secretRecords.map((secretRecord) => {
              const isRevealed = !!revealedSecretKeys[secretRecord.key];
              return (
                <div
                  key={secretRecord.key}
                  className={`secret-row${secretRecord.key === activeSecretKey ? " is-active" : ""}`}
                >
                  <button
                    className="secret-select"
                    onClick={() => setActiveSecretKey(secretRecord.key)}
                    type="button"
                  >
                    <span className="secret-key">{secretRecord.key}</span>
                    <span className="secret-preview">
                      {isRevealed ? secretRecord.value : maskSecretValue(secretRecord.value)}
                    </span>
                  </button>
                  <div className="secret-actions">
                    <button onClick={() => toggleSecretReveal(secretRecord.key)} type="button">
                      {isRevealed ? "Hide" : "Show"}
                    </button>
                    <button onClick={() => void copySecretValue(secretRecord.value)} type="button">
                      Copy
                    </button>
                  </div>
                </div>
              );
            })}
          </div>

          <div className="editor-panel">
            {activeSecretRecord ? (
              <>
                <div className="editor-header">
                  <div>
                    <p className="eyebrow">Editing</p>
                    <h3>{activeSecretRecord.key}</h3>
                  </div>
                  <span className="pill">{activeSecretRecord.length} chars</span>
                </div>
                <textarea
                  className="secret-editor"
                  onChange={(event) => setEditingSecretValue(event.target.value)}
                  spellCheck={false}
                  value={editingSecretValue}
                />
                <div className="editor-actions">
                  <button className="primary-button" disabled={isBusy} onClick={() => void saveSecretValue()} type="button">
                    Save through sops
                  </button>
                  <button
                    className="secondary-button"
                    onClick={() => setEditingSecretValue(activeSecretRecord.value)}
                    type="button"
                  >
                    Revert draft
                  </button>
                </div>
              </>
            ) : (
              <div className="empty-state">Select a secret key to edit it.</div>
            )}
          </div>
        </section>
      </main>
    </div>
  );
}
