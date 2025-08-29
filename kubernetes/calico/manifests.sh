#!/bin/bash

set -euo pipefail

parent=${1:?Must provide parent org as first argument}
version="${2:-v3.30.2}"

# Check we have the required tools installed to run the script
cmds="
  crane
  curl
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

# Apply the tigera operator manifests
kubectl create -f - < <(curl -sSf "https://raw.githubusercontent.com/projectcalico/calico/${version}/manifests/tigera-operator.yaml" | sed "s|quay.io/tigera/operator|cgr.dev/${parent}/tigera-operator|g")
if ! kubectl get crd installations.operator.tigera.io &>/dev/null; then
  kubectl create -f "https://raw.githubusercontent.com/projectcalico/calico/${version}/manifests/operator-crds.yaml"
fi

# Create the installation and the image set
cat <<***REMOVED*** | kubectl apply -f -
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  variant: Calico
  registry: cgr.dev
  imagePath: ${parent}
  imagePrefix: calico-
---
apiVersion: operator.tigera.io/v1
kind: ImageSet
metadata:
  name: calico-${version}
spec:
  images:
    - image: calico/apiserver
      digest: $(crane digest cgr.dev/${parent}/calico-apiserver:${version})
    - image: calico/node
      digest: $(crane digest cgr.dev/${parent}/calico-node:${version})
    - image: calico/cni
      digest: $(crane digest cgr.dev/${parent}/calico-cni:${version})
    - image: calico/kube-controllers
      digest: $(crane digest cgr.dev/${parent}/calico-kube-controllers:${version})
    - image: calico/pod2daemon-flexvol
      digest: $(crane digest cgr.dev/${parent}/calico-pod2daemon-flexvol:${version})
    - image: calico/csi
      digest: $(crane digest cgr.dev/${parent}/calico-csi:${version})
    - image: calico/typha
      digest: $(crane digest cgr.dev/${parent}/calico-typha:${version})
    - image: calico/node-driver-registrar
      digest: $(crane digest cgr.dev/${parent}/calico-node-driver-registrar:${version})
    - image: calico/key-cert-provisioner
      digest: $(crane digest cgr.dev/${parent}/calico-key-cert-provisioner:${version})
    # This isn't used on Linux, but it needs to have a value containing a valid digest.
    #- image: calico/node-windows
    #  digest: sha256:0000000000000000000000000000000000000000000000000000000000000000
***REMOVED***

# Wait for the tigera-operator
kubectl rollout status deployment tigera-operator -n tigera-operator --timeout 3m

# Wait for everything else to become ready
kubectl wait --for condition=ready installation.operator.tigera.io/default --timeout=5m
kubectl rollout status daemonset calico-node -n calico-system --timeout 5m
kubectl rollout status deployment calico-kube-controllers -n calico-system --timeout 5m
kubectl rollout status deployment calico-typha -n calico-system --timeout 5m
kubectl rollout status daemonset csi-node-driver -n calico-system --timeout 5m
