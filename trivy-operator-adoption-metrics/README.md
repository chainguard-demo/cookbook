# Trivy Operator Chainguard Adoption Metrics

This example demonstrates how to use the Trivy Operator and Kube State Metrics
to monitor and visualize adoption of Chainguard images in a Kubernetes cluster.

## Pre-requisites

The examples in this documentation assume that you have a Kubernetes cluster
with the following components:

- [Trivy Operator](https://github.com/aquasecurity/trivy-operator)
- [Kube State Metrics](https://github.com/kubernetes/kube-state-metrics)
- [Prometheus](https://github.com/prometheus/prometheus)
- [Grafana](https://github.com/grafana/grafana)

See [Demo](#demo) for an example of a script which stands up a local cluster
with all of these installed.

## How To

1. Give `kube-state-metrics` permission to read `VulnerabilityReport` resources.

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kube-state-metrics-trivy-reports
rules:
  - apiGroups: ["aquasecurity.github.io"]
    resources: ["vulnerabilityreports"]
    verbs: ["list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kube-state-metrics-trivy-reports
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: kube-state-metrics-trivy-reports
subjects:
  - kind: ServiceAccount
    name: kube-state-metrics
    namespace: monitoring
```

2. Create a [`CustomResourceStateMetrics`
   config](https://github.com/kubernetes/kube-state-metrics/blob/main/docs/metrics/extend/customresourcestate-metrics.md)
   that exports the OS name and family from each report.

```yaml
# passed as kube-state-metrics.customResourceState.config in the
# kube-prometheus-stack Helm chart values  or --custom-resource-state-config as
# a flag to kube-state-metrics
kind: CustomResourceStateMetrics
spec:
  resources:
    - groupVersionKind:
        group: aquasecurity.github.io
        version: v1alpha1
        kind: VulnerabilityReport
      metricNamePrefix: trivy_operator
      labelsFromPath:
        namespace: [metadata, namespace]
        name:      [metadata, name]
      metrics:
        - name: vulnerability_report_info
          help: "OS release info from trivy-operator VulnerabilityReports"
          each:
            type: Info
            info:
              labelsFromPath:
                image_repository: [report, artifact, repository]
                image_tag:        [report, artifact, tag]
                os_family:        [report, os, family]
                os_name:          [report, os, name]
```

This produces a `trivy_operator_vulnerability_report_info` metric for each
report, labelled with `os_family` and `os_name`.

3. Ensure Prometheus is scraping the metrics from the Trivy Operator too.

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: trivy-operator
  namespace: trivy-system
  labels:
    # so kube-prometheus-stack's Prometheus picks it up; adjust to match your
    # Prometheus resource's serviceMonitorSelector
    release: kube-prometheus-stack
spec:
  namespaceSelector:
    matchNames: [trivy-system]
  selector:
    matchLabels:
      app.kubernetes.io/name: trivy-operator
      app.kubernetes.io/instance: trivy-operator
  endpoints:
    - port: metrics
      honorLabels: true
```

4. Query the % of reports whose OS family is `chainguard`.

```promql
100
  * sum(trivy_operator_vulnerability_report_info{os_family="chainguard"})
  / sum(trivy_operator_vulnerability_report_info)
```

5. Query the number of reports by OS name and family.

```promql
sum by (os_family, os_name) (trivy_operator_vulnerability_report_info)
```

6. Query the number of vulnerabilities by OS name and family.

```promql
sum by (os_family, os_name) (
    sum by (namespace, name) (trivy_image_vulnerabilities)
  * on (namespace, name) group_left(os_family, os_name)
    trivy_operator_vulnerability_report_info
)
```

7. Query the average number of vulnerabilities per workload by OS name and
   family.

```promql
avg by (os_family, os_name) (
    sum by (namespace, name) (trivy_image_vulnerabilities)
  * on (namespace, name) group_left(os_family, os_name)
    trivy_operator_vulnerability_report_info
)
```

See [`dashboard.json`](dashboard.json) for an example of a Grafana dashboard
that visualizes these and other queries.

## Demo

This demo bootstraps a local cluster with an end to end example of the solution.

### Pre-requisites

You must have a Chainguard organization that includes these charts:

- `charts/kube-prometheus-stack`

And these images:

- `busybox`
- `grafana`
- `k8s-sidecar`
- `kube-state-metrics`
- `kube-webhook-certgen`
- `nginx`
- `node`
- `prometheus`
- `prometheus-admission-webhook`
- `prometheus-alertmanager`
- `prometheus-config-reloader`
- `prometheus-node-exporter`
- `prometheus-operator`
- `python`
- `redis`
- `trivy` (uses the `-dev` variant — the scan job needs a shell)
- `trivy-operator`

You must also have these required tools on `PATH`:

- `kind`
- `kubectl`
- `helm`
- `chainctl`
- `docker`
- `base64`

And be logged into `chainctl` with pull access to `cgr.dev/<org-name>/*`.

If `chainctl auth token --audience=cgr.dev` fails, run:

```sh
chainctl auth login --audience cgr.dev
chainctl auth configure-docker
```

For `helm` to pull OCI charts from `cgr.dev` transparently, point
`HELM_REGISTRY_CONFIG` at your Docker credentials:

```sh
export HELM_REGISTRY_CONFIG=$HOME/.docker/config.json
```

### Run

Run `./bootstrap.sh <org-name>` to stand up a local `kind` cluster that
demonstrates the solution. 

Provide the name of your Chainguard organization as the first argument.

Once bootstrap completes:

```sh
# Grafana → open "Trivy Operator - Chainguard Adoption" (admin / admin)
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80

# Prometheus
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090
```
