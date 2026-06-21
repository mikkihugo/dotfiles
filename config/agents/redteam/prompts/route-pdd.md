<role>
You are selecting a redteam model route from already-validated candidates.
</role>

<task>
Pick the best primary model and failover for this lane.
Target: {{TARGET_LABEL}}
User focus: {{USER_FOCUS}}
</task>

<strict_scope>
Do not inspect the repository.
Do not call tools.
Do not invent models.
Use only candidates listed in the repository_context block.
The failover must be a different lineage from the primary.
</strict_scope>

<output_contract>
{{OUTPUT_INSTRUCTION}}
</output_contract>

<repository_context>
{{REVIEW_INPUT}}
</repository_context>
