# Review record

Review mode: inline checklist fallback. `external-review-unavailable`: all six
local agent slots were occupied at review time and no attached Redteam route was
available. This record is therefore not an independent-model review.

Base: `origin/main` task baseline.

Coordinator review: **APPROVE**. A fresh native-Sol review attempt timed out
without a finding; the coordinator then independently re-ran the focused
boundary test (2/2), preferences test (1/1), and `repo vcs diff --check`, and
confirmed that only the four OpenAI residents are registered and that gateway
profiles are durable/profile-only.

## Strengths

- The resident registry is explicit and limited to four OpenAI sources in
  `config/codex/config.toml:42-61`.
- Home Manager links the same four files beneath `.codex/agents` and puts the
  five gateway configurations outside that directory in
  `home/modules/files.nix:94-139`.
- The preference merger now overwrites both top-level model and provider keys
  while preserving unrelated TOML entries; its behavioral regression test
  covers the previous `llm-gateway` provider drift.
- The profile-boundary test checks the registry, source directory, Home Manager
  links, per-profile provider/search constraints, and catalog-supported
  DeepSeek effort.

## Issues

### Critical

None found in the static implementation review.

### Important

None found in the static implementation review.

### Minor / remaining proof boundary

1. Fresh execution of `external-reasoner` and `external-reviewer` is not an
   acceptance proof for this change. The gateway currently returns separate
   protocol/conformance errors for those profiles, so this change proves the
   local safety boundary and provisioning only. Re-run bounded ephemeral calls
   after that runtime issue is fixed.

2. `purpose-validate-work` is not installed in the dotfiles development shell.
   JSON syntax and repository checks are run, but the optional work-packet
   schema validator remains unavailable.

## Assessment

Ready to merge for the bounded configuration contract, subject to Home Manager
activation and post-activation filesystem inspection. The external gateway
execution issue is explicitly outside this configuration slice and must not be
reported as fixed.
