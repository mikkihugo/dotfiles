# Independent dotfiles review

Root: /home/mhugo/.dotfiles-worktrees/codex-gpt6-settings-11f40c711b04
Review base: 26441f9c (repo vcs log); reviewed current working-tree diff plus untracked startup scripts and work packet. Reviewer only; no source edits.

## Verdict

No remaining concrete code findings in the reviewed settings, startup dispatch, or help-test changes. Publication readiness is conditional on the owner's full repo check and finalized evidence bundle; these are not yet claimed by this review.

## Evidence

- Exact-root direnv entry succeeded; repo resolved within this worktree; repo check nix passed.
- Current seed/shared TOML both select gpt-6-astra, medium reasoning and all three requested flags. Shared whitelist now saves/applies those flags; existing unrelated-profile/role preservation flow remains unchanged.
- Independent repo test codex-preferences: 3 tests pass, covering defaults and repeated save/apply preserving external profile, reviewer role, personality and unmanaged feature.
- Independent repo vcs test: contract passes. Updated help test still requires empty fake-Git log for both generated facade and direct backend help; the backend usage assertion remains. No-mutation proof was retained, not removed merely to pass generated help wording.
- Initially reproduced two check-entry valid-environment fixture failures. Worker independently diagnosed inherited BASH_ENV auto-direnv resetting fixture PATH. Current test lines25/56 clear BASH_ENV only in isolated subprocess fixtures; production guard unchanged. Independent retry repo test check-entry: 2 tests pass, including valid pure/impure, missing shell, fallback, foreign-root, malformed args, and no-full-gate markers.
- Startup guard checks shell class, fallback, nix availability, exact repo executable and foreign DIRENV_DIR rejection. Declared check nix route precedes aggregate check and cannot invoke the full gate. Explicit invalid aggregate arguments fail before profile probing.
- Scoped AGENTS instructions accurately describe bounded startup and declared focused tests. Generated repo help still has older unconditional direnv allow prose; it predates this change and the scoped conditional-allow instruction wins. No expansion requested.
- Workspec scope includes all changed source files and help-test change. Snapshot SHA256 binding verified. Requirement/delta duplicates agree; packet adds no fabricated authority. Preflight honestly says structurally valid / authorizes_execution=false. Evidence bundle was absent at inspection while owner was still running full gate; owner must finalize/validate before publication.

## Limits

No Home Manager activation, live Codex runtime acceptance, publication or remote readback performed. Source-only settings match the supplied purpose contract; live config is expressly untouched. Full gate is being run by the owning worker. This review does not turn proposed Work Decision state into authorization.

## Reviewed byte bindings
config/codex/config.toml sha256=fecfa69bcec6b1ae5e2a3ebc41dbcfcc61c5846b710fc27427fcb25fb3e6dce4
config/codex/shared-preferences.toml sha256=175a662b64d81e9e196d2003f8385e2f4fbd312c3563096bf51ba1c7e8f2411c
scripts/codex-preferences sha256=6204790c7c9771175c920623e8557ac969f236083c038eaa8a8f0c964c44547a
scripts/test-codex-preferences.py sha256=0249b515372021df90f39d73da342500ead456074f1183ae8db35980434e67e4
scripts/repo-check-nix.sh sha256=23cff1e30d58bbd5812e2b7e41edea5577cedb36f6bcdfdeaf74ade60f2a7a28
scripts/repo-check.sh sha256=eb45c35118f8063c90fbc555923f19171831184de5876b13bedf1950bbaa9b90
scripts/test-repo-check-entry.py sha256=9c398abf0c5c267d71b7333c2195f5ff4e678a4982aef039a3e9697fab36b533
scripts/test-repo-vcs.sh sha256=35c8285d4a8bdf0e7650c98b1b41f176ac17d1c875f1dae641c0d39caf326761
bin/repo sha256=bfdc79d5a4ba684d52063a896394a3967ff32137a6cd3e8c635782d2759e346d
.purpose/commands.json sha256=488e4d3f966ee41ef7aa9f60ad6f23246e6b64f1e1223ba1979e043d2c218ad2
AGENTS.md sha256=89f13b395ad59b9cd9bb1d2ee0b262bda5861fef26fc0e5e16619e775e886120
devenv.repo-commands.nix sha256=c9938009fbd883c96ce67d605993a42570095fd900a525585ee02a1273bef37f

## Follow-up review: hosted-search test expectations

Reviewed facade diff and surrounding current test. Exactly two model assertions at lines75/82 move from gpt-5.6-sol to requested gpt-6-astra for seed/shared config. OpenAI provider, exact resident set, external profile model/provider, hosted-search disabled and activation-isolation checks remain intact. No findings. Workspec allowed scope includes this test. Full suite retry remains owner verification.
scripts/test-codex-hosted-search.mjs sha256=81b83b95c37ab6cad508deac8b1a8589da77b80a89230b190071d0d087d52e15

## Follow-up review: precommit formatting and evidence excerpt

Current Nix empty module formatting and shell guard/dispatch formatting preserve behavior. The line-scoped SC2016 annotation correctly documents the intentionally literal recovery command; no checks disabled globally. No findings in this delta. Owner reports shellcheck passes. Raw failure evidence preserved separately; tracked sanitized excerpt retains the actual failure and no fake successful output. Updated source bytes:
scripts/repo-check-nix.sh sha256=2382a824507c87846857d509ec1c68499e8ad6a38083e7f606680e89c3d53116
scripts/repo-check.sh sha256=09eb9b931f7ba982cad4fd7aa85535bc7e062f9575c3e1e80b213e149a72f348
devenv.repo-commands.nix sha256=1f97d7df70c74ce93c5e859e686d8f63a929fb6a213ec101ff591824c6b80880
