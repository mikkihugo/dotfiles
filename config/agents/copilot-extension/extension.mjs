// Extension: agent-harness-suite
// Cross-CLI agent harness: 21 process skills + redteam adversarial review tools + lifecycle hooks.
//
// Skills are discovered from ~/.copilot/skills/ (symlinked from .dotfiles).
// This extension registers the 3 redteam scripts as agent-callable tools
// and lifecycle hooks for context injection and pre-commit verification.
//
// Purpose: give Copilot native tool access to the redteam panel without
// requiring the agent to shell out manually for every command.
// Consumer: Copilot CLI agent (via joinSession).
// Failure consequence: agent must fall back to bash tool for redteam — slower,
// no structured tool schema, no permission gating.
// Falsifier: the agent calls redteam_review and gets a structured result
// without invoking bash.

import { joinSession } from "@github/copilot-sdk/extension";
import { execFile } from "node:child_process";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

// Resolve the redteam bundle root.
// ~/.dotfiles/config/agents/redteam/ has the scripts.
const REDTEAM_ROOT = join(homedir(), ".dotfiles/config/agents/redteam");
const REDTEAM_SCRIPTS = join(REDTEAM_ROOT, "scripts");

function runScript(scriptName, args = []) {
    return new Promise((resolve) => {
        const scriptPath = join(REDTEAM_SCRIPTS, scriptName);
        if (!existsSync(scriptPath)) {
            resolve(`Error: script not found: ${scriptPath}`);
            return;
        }
        execFile("node", [scriptPath, ...args], {
            timeout: 600_000,
            maxBuffer: 10 * 1024 * 1024,
            cwd: REDTEAM_ROOT,
        }, (err, stdout, stderr) => {
            if (err) {
                resolve(stderr || err.message);
            } else {
                resolve(stdout);
            }
        });
    });
}

const session = await joinSession({
    tools: [
        {
            name: "redteam_panel",
            description: "Run a cross-model adversarial review panel. Modes: review, architect, plan, decision, hack, bughunt, harvest, verify, ultrareview. Pass --mode <mode> plus additional flags like --input <path>, --repo-root <dir>, --wait, --background.",
            parameters: {
                type: "object",
                properties: {
                    mode: {
                        type: "string",
                        description: "Review mode",
                        enum: ["review", "architect", "plan", "decision", "hack", "bughunt", "harvest", "verify", "ultrareview"],
                    },
                    input: {
                        type: "string",
                        description: "Input file path (plan, doc, or diff to review)",
                    },
                    repo_root: {
                        type: "string",
                        description: "Repository root directory for code review",
                    },
                    focus: {
                        type: "string",
                        description: "Focus area for the review (e.g. 'security', 'performance')",
                    },
                    wait: {
                        type: "boolean",
                        description: "Wait for completion (foreground). Default: false (background)",
                    },
                    extra_flags: {
                        type: "string",
                        description: "Additional raw flags to pass through (e.g. '--n 4 --verify')",
                    },
                },
                required: ["mode"],
            },
            handler: async (args) => {
                const flags = ["--mode", args.mode];
                if (args.input) flags.push("--input", args.input);
                if (args.repo_root) flags.push("--repo-root", args.repo_root);
                if (args.focus) flags.push("--focus", args.focus);
                if (args.wait) flags.push("--wait");
                if (args.extra_flags) flags.push(...args.extra_flags.split(/\s+/).filter(Boolean));
                return await runScript("panel.mjs", flags);
            },
        },
        {
            name: "redteam_companion",
            description: "Manage background redteam jobs. Subcommands: status, result <job-id>, cancel <job-id>, setup, provider-status.",
            parameters: {
                type: "object",
                properties: {
                    subcommand: {
                        type: "string",
                        description: "Companion subcommand",
                        enum: ["status", "result", "cancel", "setup", "provider-status"],
                    },
                    job_id: {
                        type: "string",
                        description: "Job ID (required for result and cancel)",
                    },
                },
                required: ["subcommand"],
            },
            handler: async (args) => {
                const flags = [args.subcommand];
                if (args.job_id) flags.push(args.job_id);
                return await runScript("companion.mjs", flags);
            },
        },
        {
            name: "redteam_bench",
            description: "Benchmark all available model lineages. Runs the panel across every lineage, collecting timing and quality metrics.",
            parameters: {
                type: "object",
                properties: {
                    model_filter: {
                        type: "string",
                        description: "Optional model name filter",
                    },
                },
            },
            handler: async (args) => {
                const flags = [];
                if (args.model_filter) flags.push("--model", args.model_filter);
                return await runScript("lane-bench.mjs", flags);
            },
        },
    ],
    hooks: {
        onSessionStart: async () => {
            // Inject redteam availability context
            if (existsSync(REDTEAM_SCRIPTS)) {
                return {
                    additionalContext: "Redteam adversarial review tools are available. Use the redteam_panel tool for cross-model code/diff/plan review (modes: review, architect, plan, decision, hack, bughunt, harvest, verify, ultrareview). Use redteam_companion for background job management.",
                };
            }
        },
    },
});
