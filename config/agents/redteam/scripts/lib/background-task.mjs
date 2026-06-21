/**
 * background-task.mjs — lightweight BackgroundTask wrapper for redteam panel runs.
 *
 * Purpose: give panel.mjs a settle-style contract (start + sink.settle) that mirrors
 *          agent-core's ProcessBackgroundTask, without pulling the full kaos/agent-core
 *          dependency graph into the redteam scripts today.
 *
 * Consumer: panel.mjs runOne (via spawnTask). Future work can swap the implementation
 *           for the real @moonshot-ai/agent-core BackgroundTask when a concrete need
 *           (shared memory, sub-second startup, hard supervisor) appears.
 */

import { spawn } from "node:child_process"

/**
 * Spawn a child process as a BackgroundTask.
 *
 * @param {string} command
 * @param {string[]} args
 * @param {Object} [options]
 * @param {string} [options.cwd]
 * @param {Object} [options.env]
 * @param {string} [options.description]
 * @returns {{id:string, start:(sink:BackgroundTaskSink)=>Promise<void>}}
 */
export function spawnTask(command, args, options = {}) {
  const id = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`
  const description = options.description || `${command} ${args[0] || ""}`.trim()

  return {
    id,
    async start(sink) {
      const child = spawn(command, args, {
        cwd: options.cwd,
        env: { ...process.env, ...options.env },
        stdio: ["ignore", "pipe", "pipe"],
      })

      const appendStdout = (chunk) => {
        try { sink.appendOutput(String(chunk)) } catch {}
      }
      const appendStderr = typeof sink.appendStderr === "function"
        ? (chunk) => { try { sink.appendStderr(String(chunk)) } catch {} }
        : (chunk) => { try { process.stderr.write(chunk) } catch {} }
      child.stdout.setEncoding("utf8")
      child.stderr.setEncoding("utf8")
      child.stdout.on("data", appendStdout)
      child.stderr.on("data", appendStderr)

      const requestStop = () => {
        try { child.kill("SIGTERM") } catch {}
      }
      if (sink.signal?.aborted) {
        requestStop()
      } else if (sink.signal) {
        sink.signal.addEventListener("abort", requestStop, { once: true })
      }

      child.on("close", (code, signal) => {
        const status = sink.signal?.aborted
          ? "killed"
          : code === 0
            ? "completed"
            : "failed"
        sink.settle({ status, exitCode: code ?? null, signal: signal || null }).catch(() => {})
      })

      child.on("error", (err) => {
        sink.settle({ status: "failed", error: err?.message || String(err) }).catch(() => {})
      })
    },
  }
}

/**
 * Minimal sink shape expected by start().
 * Consumers can pass a custom sink; this factory provides a no-op default.
 */
export function createNullSink() {
  return {
    signal: null,
    appendOutput() {},
    async settle() {},
  }
}
