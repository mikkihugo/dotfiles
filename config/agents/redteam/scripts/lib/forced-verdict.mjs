/**
 * forced-verdict.mjs — research-grade convergence checklist.
 *
 * After many tool calls without a verdict, the runner injects this rigid,
 * numbered checklist. The model must execute the steps in order; the final
 * step forces an immediate submit_verdict tool call.
 *
 * This follows the "Ralph loop" / verify-gated completion pattern from
 * current long-horizon agent research (Anthropic 2025-2026). We do not rely
 * on the model remembering or self-regulating.
 */

export const DEFAULT_FORCE_VERDICT_AFTER_STEPS = 90

export const FORCED_VERDICT_CHECKLIST = `
You have now performed a large number of tool calls without reaching a verdict.

You MUST complete the following steps **in exact order** before producing any further reasoning or tool calls. This is a mandatory procedure designed to force convergence on long reviews.

1. In 5–7 bullet points, list the most important claims, hypotheses, or potential issues you have formed during this review.

2. For each claim in step 1, state whether you have **direct evidence** from an actual tool call (Read, Grep, Glob, fetch, etc.). Cite the exact file:line, command, or output that supports it. If you have no direct evidence for a claim, explicitly mark it "UNVERIFIED".

3. Identify the single highest-risk area or claim that you have **not yet fully verified** with concrete tool evidence. Be specific. For every artifact you reference, explicitly state whether it is (a) present in source, (b) wired on a production boot path, (c) covered by a falsifier that would fail if the claim is false.

4. Decision point: With the evidence gathered so far, can you reach a confident, evidence-based verdict on the review target, or is the review exhausted without sufficient coverage of the highest-risk area?

5. If you can reach a confident verdict → immediately call the submit_verdict tool with your current assessment. Do not write JSON or the verdict as prose — use the tool.

6. If you cannot reach a confident verdict → call submit_verdict with verdict="needs-attention" and a single finding titled "Review exhausted without conclusion". The finding body must name the highest-risk unchecked area (from step 3) and the specific additional evidence that would be required to conclude.

You are not allowed to continue tool use, open-ended reasoning, or any other actions after completing these six steps. Execute the checklist now and produce the required submit_verdict tool call.
`.trim()

/**
 * Return the step count at which the forced-verdict checklist should be injected.
 */
export function getForceVerdictStepCount() {
  return Number(process.env.REDTEAM_FORCE_VERDICT_AFTER_STEPS) || DEFAULT_FORCE_VERDICT_AFTER_STEPS
}
