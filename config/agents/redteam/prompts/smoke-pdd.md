<role>
You are running a provider route smoke test.
</role>

<task>
Verify that the requested model route can return a valid structured response.
Target: {{TARGET_LABEL}}
User focus: {{USER_FOCUS}}
</task>

<strict_scope>
Do not inspect the repository.
Do not call tools.
Do not perform a code review.
Use only the text in the repository_context block.
</strict_scope>

<output_contract>
Return ONLY valid JSON matching this schema:
{{SCHEMA}}

Use `approve` if the route, authentication, model selection, and JSON output path work.
Use `needs-attention` only if this prompt itself reveals a provider, auth, model, timeout, thinking, or harness execution failure.
For a successful smoke, set `findings` and `next_steps` to empty arrays.
</output_contract>

<repository_context>
{{REVIEW_INPUT}}
</repository_context>
