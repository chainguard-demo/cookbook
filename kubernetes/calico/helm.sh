#!/bin/bash

set -euo pipefail

parent=${1:?Must provide parent org as first argument}

# Check we have the required tools installed to run the script
cmds="
  crane
  helm
  yq
  kubectl
"
missing_cmds=""
for cmd in ${cmds}; do
  if ! command -v "${cmd}" &> /dev/null; then
    missing_cmds+="${cmd} "
  fi
done
if [[ -n "${missing_cmds}" ]]; then
  echo "Missing required commands: ${missing_cmds}" >&2
  exit 1
fi

# Get the version so we know what images to
# resolve digests for
version=$(helm show chart helm-chart | yq '.appVersion')

# Install the chart
helm dependency update helm-chart/
helm upgrade calico helm-chart/ \
  --install \
  --create-namespace \
  --namespace tigera-operator \
  --set tigera-operator.tigeraOperator.image="${parent}/tigera-operator" \
  --set tigera-operator.installation.imagePath="${parent}" \
  --set imageSet.apiserver.digest="$(crane digest cgr.dev/${parent}/calico-apiserver:${version})" \
  --set imageSet.node.digest="$(crane digest cgr.dev/${parent}/calico-node:${version})" \
  --set imageSet.cni.digest="$(crane digest cgr.dev/${parent}/calico-cni:${version})" \
  --set imageSet.kubeControllers.digest="$(crane digest cgr.dev/${parent}/calico-kube-controllers:${version})" \
  --set imageSet.pod2daemonFlexvol.digest="$(crane digest cgr.dev/${parent}/calico-pod2daemon-flexvol:${version})" \
  --set imageSet.csi.digest="$(crane digest cgr.dev/${parent}/calico-csi:${version})" \
  --set imageSet.typha.digest="$(crane digest cgr.dev/${parent}/calico-typha:${version})" \
  --set imageSet.nodeDriverRegistrar.digest="$(crane digest cgr.dev/${parent}/calico-node-driver-registrar:${version})" \
  --set imageSet.keyCertProvisioner.digest="$(crane digest cgr.dev/${parent}/calico-key-cert-provisioner:${version})"

# Wait for the tigera-operator
kubectl rollout status deployment tigera-operator -n tigera-operator --timeout 3m

# Wait for everything else to become ready
kubectl wait --for condition=ready installation.operator.tigera.io/default --timeout=5m
kubectl rollout status daemonset calico-node -n calico-system --timeout 5m
kubectl rollout status deployment calico-kube-controllers -n calico-system --timeout 5m
kubectl rollout status deployment calico-typha -n calico-system --timeout 5m
kubectl rollout status daemonset csi-node-driver -n calico-system --timeout 5m
