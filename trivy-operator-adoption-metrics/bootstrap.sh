#!/usr/bin/env bash
# Stand up a local kind cluster running trivy-operator + kube-prometheus-stack
# built from Chainguard images (from the given ORG_NAME under cgr.dev),
# with kube-state-metrics configured to export a CustomResourceStateMetrics
# metric for every trivy-operator VulnerabilityReport, plus a Grafana dashboard
# that breaks down OS family / OS release across scanned workloads.
#
# Usage:
#   ./bootstrap.sh <ORG_NAME>
#
# See pre-requisites in the README.md.

set -euo pipefail

usage() { echo "Usage: $(basename "$0") <ORG_NAME>" >&2; exit 1; }
[[ $# -eq 1 ]] || usage
ORG_NAME="$1"

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CLUSTER="${CLUSTER:-trivy-operator-adoption}"
TRIVY_OPERATOR_VERSION="${TRIVY_OPERATOR_VERSION:-0.30.0}"
KPS_VERSION="${KPS_VERSION:-88.3.0}"

need() { command -v "$1" >/dev/null || { echo "missing: $1" >&2; exit 1; }; }
for c in kind kubectl helm chainctl docker base64; do need "$c"; done

tmp=$(mktemp -d); trap 'rm -rf "${tmp}"' EXIT

if kind get clusters | grep -qx "${CLUSTER}"; then
  echo "==> deleting existing kind cluster '${CLUSTER}'"
  kind delete cluster --name "${CLUSTER}"
fi
echo "==> creating kind cluster '${CLUSTER}'"
kind create cluster --name "${CLUSTER}" --wait 3m
kubectl config use-context "kind-${CLUSTER}" >/dev/null

echo "==> installing cgr.dev pull credentials on kind node"
TOKEN=$(chainctl auth token --audience=cgr.dev)
AUTH=$(printf '_token:%s' "${TOKEN}" | base64 | tr -d '\n')
cat > "${tmp}/config.json" <<EOF
{"auths":{"cgr.dev":{"auth":"${AUTH}"}}}
EOF
NODE="${CLUSTER}-control-plane"
docker cp "${tmp}/config.json" "${NODE}:/var/lib/kubelet/config.json"
docker exec "${NODE}" systemctl restart kubelet.service
kubectl wait --for=condition=Ready node --all --timeout=2m

echo "==> rendering kps-values.yaml (ORG=${ORG_NAME})"
sed "s|__ORG__|${ORG_NAME}|g" "${DIR}/kps-values.yaml" > "${tmp}/kps-values.yaml"

# Node-level creds at /var/lib/kubelet/config.json let kubelet pull the
# workload images, but trivy-operator scan-job pods fetch each target image's
# manifest themselves and don't inherit that node auth. Without a namespace-
# scoped pull secret referenced via imagePullSecrets on the scanned pod (or
# its ServiceAccount), scans of private cgr.dev/${ORG_NAME}/* workloads fail
# and no VulnerabilityReport is produced for them. Create a "regcred" secret
# in each namespace we'll scan and reference it from the helm values below.
echo "==> creating cgr.dev pull secrets in trivy-system, monitoring, cg-workloads"
for ns in trivy-system monitoring cg-workloads; do
  kubectl create namespace "${ns}" --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n "${ns}" create secret docker-registry regcred \
    --docker-server=cgr.dev \
    --docker-username=_token \
    --docker-password="${TOKEN}" \
    --dry-run=client -o yaml | kubectl apply -f -
done

echo "==> preparing dashboard ConfigMap"
kubectl -n monitoring create configmap trivy-os-dashboard \
  --from-file=trivy-os-breakdown.json="${DIR}/dashboard.json" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n monitoring label configmap trivy-os-dashboard grafana_dashboard=1 --overwrite >/dev/null

# KPS is installed BEFORE trivy-operator so the ServiceMonitor CRD
# (monitoring.coreos.com/v1) exists at trivy-operator render time. The aqua
# chart guards its ServiceMonitor template with a .Capabilities.APIVersions.Has
# check — if the CRD isn't present when trivy-operator is installed, the
# ServiceMonitor is silently skipped, Prometheus never scrapes the operator's
# /metrics endpoint, and trivy_image_vulnerabilities never shows up.
echo "==> installing kube-prometheus-stack (Chainguard chart)"
helm upgrade --install kube-prometheus-stack \
  "oci://cgr.dev/${ORG_NAME}/charts/kube-prometheus-stack" \
  --namespace monitoring \
  --version "${KPS_VERSION}" \
  -f "${tmp}/kps-values.yaml" \
  --wait --timeout 10m

echo "==> installing trivy-operator (aqua chart, Chainguard images)"
helm repo add aqua https://aquasecurity.github.io/helm-charts/ >/dev/null 2>&1 || true
helm repo update aqua >/dev/null
helm upgrade --install trivy-operator aqua/trivy-operator \
  --namespace trivy-system --create-namespace \
  --version "${TRIVY_OPERATOR_VERSION}" \
  --set operator.builtInTrivyServer=true \
  --set operator.clusterComplianceEnabled=false \
  --set trivy.storageClassEnabled=false \
  --set trivy.ignoreUnfixed=true \
  --set operator.scanJobTimeout=5m \
  --set image.registry=cgr.dev \
  --set image.repository="${ORG_NAME}/trivy-operator" \
  --set image.tag=0.28 \
  --set trivy.image.registry=cgr.dev \
  --set trivy.image.repository="${ORG_NAME}/trivy" \
  --set trivy.image.tag=0.65-dev \
  --set "imagePullSecrets[0].name=regcred" \
  --set serviceMonitor.enabled=true \
  --set serviceMonitor.labels.release=kube-prometheus-stack \
  --wait --timeout 5m

echo "==> deploying Chainguard example workloads (ORG=${ORG_NAME})"
sed "s|__ORG__|${ORG_NAME}|g" "${DIR}/workloads.yaml" | kubectl apply -f -

cat <<EOF

Setup complete. Next:

  # Grafana (admin / admin), dashboard: "Trivy - OS Release Breakdown"
  kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80

  # Prometheus
  kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090

  # Raw KSM metrics
  kubectl -n monitoring port-forward svc/kube-prometheus-stack-kube-state-metrics 8080:8080
  curl -s localhost:8080/metrics | grep trivy_operator_vulnerability_report_info

Scans take a couple of minutes on first run (trivy-server has to pull the DB).
EOF
