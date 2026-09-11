# Runbook: wire Grafana and Loki shims into centralcloud-mcp-gateway

Date: 2026-09-11
Author: agent (kimicode-9b9dfcbc-20260911)
Scope: /srv/infra (operator-owned; agent cannot write this directly — this runbook is the operator patch)

## Why

Before this change, Grafana and Loki were operator-documented capability contracts in `mcp-fleet/shims/{grafana,loki}/instructions.md` and the Go implementations existed in `mcp-fleet/main.go` (`registerGrafana`, `registerLoki`) — but no `Deployment/mcp-fleet-grafana` or `Deployment/mcp-fleet-loki` existed in the cluster, and `centralcloud-mcp-gateway`'s `MCP_ROUTER_UPSTREAMS` did not list them. Result: `mcp_catalog_search(query="grafana")` and `mcp_catalog_search(query="loki")` returned nothing; agents had no MCP surface for Grafana alerts/dashboards/annotations or LogQL.

After this change:
- Two new Deployments (`loki-mcp`, `grafana-mcp`) in `centralcloud-mcp` namespace, each running the shared `centralcloud-mcp-fleet` image with a different `MCP_SHIM` env var.
- Two Services exposing `:8000` (loki) and `:8000` (grafana) with path `/mcp`.
- `MCP_ROUTER_UPSTREAMS` updated to include `loki` and `grafana` keys.
- `mcp_catalog_search` returns 7 grafana tools (`get_firing_alerts`, `list_alert_rules`, `search_dashboards`, `get_dashboard`, `annotate_incident`, `list_datasources`, `get_datasource_health`) and 5 loki tools (`query_logs`, `get_recent_errors`, `get_backup_summaries`, `list_log_labels`, `list_label_values`).
- `kv/grafana-mcp#api_key` provisioned as a Grafana service-account token with Viewer + Annotations Editor roles.

This runbook covers the operator-side changes that the agent cannot apply itself.

## Agent-side confirmation (already done)

- `cd singularity-engine/fabrics/tools/services/mcp-fleet && go build ./...` → succeeded
- `cd singularity-engine/fabrics/tools/services/mcp-fleet && go test -count=1 .` → `ok ... 10.477s` (no regression)
- `registerLoki` and `registerGrafana` exist in `main.go:729` and `main.go:834`
- Tests at `main_test.go:193/195` and `instructions_test.go:72/74` cover both
- `instructions.go:37/40` embeds the operator-facing capability contracts from `shims/{loki,grafana}/instructions.md`

The Go side is complete and tested. Nothing for the agent to land.

## Operator patch 1 — `loki-mcp/deployment.yaml` (new file)

Create `/srv/infra/clusters/default/tenants/centralcloud/apps/loki-mcp/deployment.yaml`:

```yaml
# loki-mcp — exposes in-cluster Loki LogQL to operations-agent for log-based
# incident triage. Uses centralcloud-mcp-fleet native Go shim (MCP_SHIM=loki).
# Tools: query_logs, get_recent_errors, get_backup_summaries,
#        list_log_labels, list_label_values.
# Agents connect via: http://loki-mcp.centralcloud-mcp.svc:8000/mcp
apiVersion: apps/v1
kind: Deployment
metadata:
  name: loki-mcp
  namespace: centralcloud-mcp
  labels:
    app.kubernetes.io/name: loki-mcp
    app.kubernetes.io/part-of: centralcloud
    app.kubernetes.io/component: mcp-shim
spec:
  replicas: 1
  strategy:
    type: RollingUpdate
  selector:
    matchLabels:
      app.kubernetes.io/name: loki-mcp
  template:
    metadata:
      labels:
        app.kubernetes.io/name: loki-mcp
        app.kubernetes.io/part-of: centralcloud
    spec:
      serviceAccountName: loki-mcp
      containers:
        - name: loki-mcp
          image: registry.centralcloud.net/centralcloud/centralcloud-mcp-fleet:0.9.16387@sha256:3bbfcb46b92fc290074c271de198c173f230fb2259f6c49970b82d4ee07da9c5 # {"$imagepolicy": "flux-system:centralcloud-mcp-fleet"}
          imagePullPolicy: Always
          env:
            - name: MCP_SHIM
              value: loki
            - name: PORT
              value: "8000"
            - name: LOKI_URL
              value: "http://loki.monitoring.svc.cluster.local:3100"
          ports:
            - {name: http, containerPort: 8000}
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
              ephemeral-storage: 100Mi
            limits:
              cpu: 200m
              memory: 128Mi
              ephemeral-storage: 500Mi
          readinessProbe:
            httpGet: {path: /health, port: http}
            initialDelaySeconds: 5
            periodSeconds: 10
            timeoutSeconds: 3
            failureThreshold: 3
          livenessProbe:
            httpGet: {path: /health, port: http}
            initialDelaySeconds: 15
            periodSeconds: 30
            timeoutSeconds: 5
            failureThreshold: 3
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL
            readOnlyRootFilesystem: true
            runAsNonRoot: true
            runAsUser: 65532
            runAsGroup: 65532
            seccompProfile:
              type: RuntimeDefault
      securityContext:
        runAsNonRoot: true
        runAsUser: 65532
        runAsGroup: 65532
        fsGroup: 65532
        fsGroupChangePolicy: OnRootMismatch
        seccompProfile:
          type: RuntimeDefault
```

(Use the same `image: ... @sha256:...` digest from `prometheus-mcp/deployment.yaml`. The `# {"$imagepolicy": ...}` annotation drives Flux image automation to keep the digest current.)

## Operator patch 2 — `loki-mcp/service.yaml` (new file)

Create `/srv/infra/clusters/default/tenants/centralcloud/apps/loki-mcp/service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: loki-mcp
  namespace: centralcloud-mcp
  labels:
    app.kubernetes.io/name: loki-mcp
    app.kubernetes.io/part-of: centralcloud
spec:
  selector:
    app.kubernetes.io/name: loki-mcp
  ports:
    - { name: http, port: 8000, targetPort: 8000 }
```

## Operator patch 3 — `loki-mcp/kustomization.yaml` (update existing)

Edit `/srv/infra/clusters/default/tenants/centralcloud/apps/loki-mcp/kustomization.yaml` to add the two new files:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - serviceaccount.yaml
  - deployment.yaml      # new
  - service.yaml         # new
```

## Operator patch 4 — `grafana-mcp/deployment.yaml` (new file)

Create `/srv/infra/clusters/default/tenants/centralcloud/apps/grafana-mcp/deployment.yaml`:

```yaml
# grafana-mcp — exposes in-cluster Grafana alerts, dashboards, datasources,
# and incident annotations. Uses centralcloud-mcp-fleet native Go shim
# (MCP_SHIM=grafana). Tools: get_firing_alerts, list_alert_rules,
# search_dashboards, get_dashboard, annotate_incident, list_datasources,
# get_datasource_health.
# Agents connect via: http://grafana-mcp.centralcloud-mcp.svc:8000/mcp
# Auth: GRAFANA_API_KEY from OpenBao via existing externalsecret.yaml.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana-mcp
  namespace: centralcloud-mcp
  labels:
    app.kubernetes.io/name: grafana-mcp
    app.kubernetes.io/part-of: centralcloud
    app.kubernetes.io/component: mcp-shim
spec:
  replicas: 1
  strategy:
    type: RollingUpdate
  selector:
    matchLabels:
      app.kubernetes.io/name: grafana-mcp
  template:
    metadata:
      labels:
        app.kubernetes.io/name: grafana-mcp
        app.kubernetes.io/part-of: centralcloud
    spec:
      serviceAccountName: grafana-mcp
      containers:
        - name: grafana-mcp
          image: registry.centralcloud.net/centralcloud/centralcloud-mcp-fleet:0.9.16387@sha256:3bbfcb46b92fc290074c271de198c173f230fb2259f6c49970b82d4ee07da9c5 # {"$imagepolicy": "flux-system:centralcloud-mcp-fleet"}
          imagePullPolicy: Always
          env:
            - name: MCP_SHIM
              value: grafana
            - name: PORT
              value: "8000"
            - name: GRAFANA_URL
              value: "http://grafana.monitoring.svc.cluster.local:3000"
            - name: GRAFANA_API_KEY
              valueFrom:
                secretKeyRef:
                  name: grafana-mcp-secret
                  key: api_key
          ports:
            - {name: http, containerPort: 8000}
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
              ephemeral-storage: 100Mi
            limits:
              cpu: 200m
              memory: 128Mi
              ephemeral-storage: 500Mi
          readinessProbe:
            httpGet: {path: /health, port: http}
            initialDelaySeconds: 5
            periodSeconds: 10
            timeoutSeconds: 3
            failureThreshold: 3
          livenessProbe:
            httpGet: {path: /health, port: http}
            initialDelaySeconds: 15
            periodSeconds: 30
            timeoutSeconds: 5
            failureThreshold: 3
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL
            readOnlyRootFilesystem: true
            runAsNonRoot: true
            runAsUser: 65532
            runAsGroup: 65532
            seccompProfile:
              type: RuntimeDefault
      securityContext:
        runAsNonRoot: true
        runAsUser: 65532
        runAsGroup: 65532
        fsGroup: 65532
        fsGroupChangePolicy: OnRootMismatch
        seccompProfile:
          type: RuntimeDefault
```

## Operator patch 5 — `grafana-mcp/service.yaml` (new file)

Create `/srv/infra/clusters/default/tenants/centralcloud/apps/grafana-mcp/service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: grafana-mcp
  namespace: centralcloud-mcp
  labels:
    app.kubernetes.io/name: grafana-mcp
    app.kubernetes.io/part-of: centralcloud
spec:
  selector:
    app.kubernetes.io/name: grafana-mcp
  ports:
    - { name: http, port: 8000, targetPort: 8000 }
```

## Operator patch 6 — `grafana-mcp/kustomization.yaml` (update existing)

Edit `/srv/infra/clusters/default/tenants/centralcloud/apps/grafana-mcp/kustomization.yaml` to add the new files:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - serviceaccount.yaml
  - externalsecret.yaml   # already exists
  - deployment.yaml       # new
  - service.yaml          # new
```

## Operator patch 7 — `MCP_ROUTER_UPSTREAMS` in gateway

Edit `/srv/infra/clusters/default/tenants/centralcloud/apps/centralcloud-mcp-gateway/deployment.yaml` at the `MCP_ROUTER_UPSTREAMS` env block (around line 121). Append two entries to the comma-separated list:

```yaml
            - name: MCP_ROUTER_UPSTREAMS
              value: >-
                repo_memory=http://repo-memory.centralcloud-mcp.svc.cluster.local:8888/mcp,
                purpose_tool=http://purpose-tool.centralcloud-mcp.svc.cluster.local:8931/mcp,
                redteam=http://redteam.centralcloud-mcp.svc.cluster.local:8933/mcp,
                context7=http://context7-mcp.centralcloud-mcp.svc.cluster.local:8000/mcp,
                deepwiki=http://deepwiki-mcp.centralcloud-mcp.svc.cluster.local:8000/mcp,
                github=http://github-mcp.centralcloud-mcp.svc.cluster.local:8000/mcp,
                kubernetes_readonly=http://kubernetes-readonly-mcp.centralcloud-mcp.svc.cluster.local:8081/mcp,
                kubernetes=http://kubernetes-mcp.centralcloud-mcp.svc.cluster.local:8080/mcp,
                observability=http://observability-mcp.centralcloud-mcp.svc.cluster.local:8097/mcp,
                oncall=http://oncall-mcp.centralcloud-mcp.svc.cluster.local:8000/mcp,
                prometheus=http://prometheus-mcp.centralcloud-mcp.svc.cluster.local:9090/mcp,
                alertmanager=http://alertmanager-mcp.centralcloud-mcp.svc.cluster.local:8000/mcp,
                cloudflare_dns=http://cloudflare-dns-mcp.centralcloud-mcp.svc.cluster.local:8000/mcp,
                uptimerobot=http://uptimerobot-mcp.centralcloud-mcp.svc.cluster.local:8000/mcp,
                forgejo=http://forgejo-mcp.forgejo.svc.cluster.local:8080/mcp,
                flux=http://flux-mcp.centralcloud-mcp.svc.cluster.local:8080/mcp,
                playwright=http://playwright-mcp.centralcloud-mcp.svc.cluster.local:8000/mcp,
                cnpg=http://cnpg-mcp.centralcloud-mcp.svc.cluster.local:8000/mcp,
                longhorn=http://longhorn-mcp.centralcloud-mcp.svc.cluster.local:8000/mcp,
                openbao=http://openbao-mcp.centralcloud-mcp.svc.cluster.local:8000/mcp,
                loki=http://loki-mcp.centralcloud-mcp.svc.cluster.local:8000/mcp,
                grafana=http://grafana-mcp.centralcloud-mcp.svc.cluster.local:8000/mcp
```

Add the `loki` and `grafana` lines at the end. Watch trailing comma — last entry must not have a trailing comma (the `>-` block parser tolerates either, but consistency matters).

## Operator patch 8 — OpenBao secret for Grafana

If not already provisioned:

1. In Grafana UI (`https://grafana.admin.centralcloud.net/org/serviceaccounts`), create a service account with role `Viewer` + `Annotations Editor`.
2. Mint an API key.
3. Store in OpenBao:
   ```
   bao kv put kv/grafana-mcp api_key="glsa_xxxxxxxxxxxx"
   ```
4. Confirm ExternalSecret syncs within 1h:
   ```
   kubectl -n centralcloud-mcp get externalsecret grafana-mcp-secret -o yaml
   kubectl -n centralcloud-mcp get secret grafana-mcp-secret -o jsonpath='{.data.api_key}' | base64 -d
   ```
   Should yield the token bytes (not empty).

## Verification (operator, post-deploy)

1. **Pods ready**:
   ```
   kubectl -n centralcloud-mcp get pods -l 'app.kubernetes.io/name in (loki-mcp,grafana-mcp)'
   # expect: loki-mcp-xxx 1/1 Running, grafana-mcp-xxx 1/1 Running
   ```

2. **Services have endpoints**:
   ```
   kubectl -n centralcloud-mcp get endpoints loki-mcp grafana-mcp
   # both should show at least one endpoint
   ```

3. **Gateway configmap picks up the new upstreams** (after Flux reconcile + rollout):
   ```
   kubectl -n centralcloud-mcp exec deploy/centralcloud-mcp-gateway -- \
     sh -c 'echo "$MCP_ROUTER_UPSTREAMS" | tr , "\n" | grep -E "^(loki|grafana)="'
   ```
   Expect two lines, one each for `loki=...` and `grafana=...`.

4. **Catalog surfaces the tools** (agent-side after Flux reconcile):
   ```
   mcp_catalog_search(query="grafana") | head -3
   mcp_catalog_search(query="loki")    | head -3
   ```
   Expect non-empty results listing the registered tools.

5. **End-to-end smoke** (operator or agent with ccgw access):
   ```
   # Loki smoke
   curl -s -X POST http://centralcloud-mcp-gateway.centralcloud-mcp.svc:8000/mcp \
     -H 'Content-Type: application/json' \
     -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"loki.list_log_labels"}}' | jq

   # Grafana smoke
   curl -s -X POST http://centralcloud-mcp-gateway.centralcloud-mcp.svc:8000/mcp \
     -H 'Content-Type: application/json' \
     -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grafana.list_datasources"}}' | jq
   ```
   Expect valid JSON-RPC responses with non-error results.

## Rollback

1. Revert the `MCP_ROUTER_UPSTREAMS` env edit (remove `loki=...` and `grafana=...` lines).
2. `kubectl -n centralcloud-mcp delete deployment loki-mcp grafana-mcp` and the two Services.
3. Revert kustomization.yaml entries (remove `deployment.yaml` and `service.yaml` from resources lists).
4. Confirm gateway is healthy and existing 19 upstreams still answer.
5. The Go code stays in `mcp-fleet/main.go` — it's inert without a running shim pod.

## Falsifier (NOT done if any one is true)

- `mcp_catalog_search(query="grafana")` returns zero hits after Flux reconcile + gateway rollout.
- `mcp_catalog_search(query="loki")` returns zero hits.
- Either pod is `0/1 Running` or `CrashLoopBackOff` after 5 minutes.
- `kubectl -n centralcloud-mcp get endpoints loki-mcp` shows `<none>`.
- Grafana smoke call returns `401 Unauthorized` (the OpenBao secret didn't sync or wrong role).
- Loki smoke call returns `502 Bad Gateway` (LOKI_URL unreachable from pod; verify DNS).
- Gateway log shows `upstream dial failed` for `loki` or `grafana`.

## Cross-references

- `mcp-fleet/main.go:729` — `registerLoki` (Go source)
- `mcp-fleet/main.go:834` — `registerGrafana` (Go source)
- `mcp-fleet/main.go:82-119` — per-shim dispatch switch (`case "loki": registerLoki(s)`, etc.)
- `mcp-fleet/instructions.go:37/40` — embedded operator-facing capability contracts
- `mcp-fleet/main_test.go:193/195`, `instructions_test.go:72/74` — test coverage
- `mcp-fleet/shims/{loki,grafana}/instructions.md` — capability contracts
- `prometheus-mcp/deployment.yaml` — template this runbook was derived from
