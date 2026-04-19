# SKILL: LLM Ops (LangFuse & LightRAG)

Manage observability, tracing, and knowledge graph retrieval for LLM applications.

## Overview
This skill provides guidance on monitoring and optimizing AI agents using LangFuse (tracing/evals) and LightRAG (graph-based RAG). It covers deployment, integration, and performance analysis.

## Capabilities
- **Observability**: Configure LangFuse to trace agent interactions and latency.
- **RAG Management**: Manage LightRAG knowledge graphs and document ingestion.
- **Evaluation**: Guidance on using RAGAS or LangFuse evals to measure answer quality.
- **Troubleshooting**: Debugging graph extraction and retrieval issues.

## Usage Guidelines

### 1. Tracing
Ensure all agent calls (OpenClaw, etc.) are traced to LangFuse for debugging and optimization.
- Check trace status in the LangFuse UI (`https://ai.hugo.dk`).

### 2. Ingestion
When adding new data (emails, docs, code):
1. Ingest into LightRAG to update the Knowledge Graph.
2. Verify that entities and relationships are correctly extracted.

### 3. Monitoring
- Monitor token usage and latency in LangFuse.
- Check LightRAG logs for ingestion errors or extraction failures.

## Common Commands
| Task | Command |
| :--- | :--- |
| Check LangFuse Pods | `kubectl get pods -n langfuse` |
| LightRAG Ingestion | `docker exec lightrag python ingest.py --dir /data/docs` |
| View Logs | `docker logs lightrag` |

## Best Practices
- **Privacy**: Be mindful of sensitive data being traced to LangFuse.
- **Model Choice**: Use 32B+ models for graph extraction in LightRAG for best results.
- **Incremental Sync**: Use file-watchers or scheduled scripts to incrementally sync data into the RAG graph.
- **Tracing Secret**: Store the LangFuse secret key securely in the Vault.
