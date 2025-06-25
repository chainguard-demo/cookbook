#!/bin/bash

set -euo pipefail

parent=${1:?Must provide parent org as first argument}
image=${2:?Must provide example image as second argument}

# Check we have the required tools installed to run the script
cmds="
  chainctl
  docker
  jq
  kind
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

# Delete existing cluster
if kind get clusters 2>/dev/null | grep -Eq '^credential-provider$'; then
  kind delete cluster --name credential-provider
fi

# Delete existing identities
while read -r id; do
  chainctl iam id delete "${id}" --yes
done < <(chainctl iam id list --parent="${parent}" -o json | jq -r '.items[] | select(.name == "kind-credential-provider") | .id')

# Build the custom kind node image. This includes the custom credentials
# provider.
echo "Building kind image..." >&2
docker build -t kind-credential-provider-node .

# Create the cluster. The kubelet is configured to call the custom credential
# provider for images in cgr.dev.
kind create cluster --name credential-provider --config kind-config.yaml

# Create an assumable identity for the default/default service account
echo "Creating the assumable identity..." >&2
IDENTITY_ID=$(chainctl iam id create kind-credential-provider \
  --parent=${parent} \
  --issuer-keys="$(kubectl get --raw /openid/v1/jwks)" \
  --identity-issuer=https://kubernetes.default.svc.cluster.local \
  --subject='system:serviceaccount:default:default' \
  --role=registry.pull \
  --yes \
  -o id
)

# Annotate the default sa with the identity. This is where the
# credential-provider gets the identity to assume for the service account.
echo "Annotating the default/default service account with the identity id..." >&2
while ! kubectl -n default get sa default &>/dev/null; do
  sleep 1
done
kubectl -n default annotate sa default credentials.chainguard.dev/identity=${IDENTITY_ID}

# Kind doesn't seem to give the control plane user the adequate permissions for
# the feature, so setup some additional RBAC
echo "Adding additional RBAC..." >&2
kubectl create -f kind-rbac.yaml

# Create a basic example pod that pulls from cgr.dev
echo "Creating an example pod..." >&2
cat <<***REMOVED*** | kubectl create -n default -f -
apiVersion: v1
kind: Pod
metadata:
  name: example
spec:
  serviceAccountName: default
  containers:
  - name: example
    image: cgr.dev/${parent}/${image}
    command: ["/bin/sh", "-c"]
    args: ["while true; do sleep 3600; done"]
***REMOVED***

echo "Waiting for the example pod to become ready..." >&2
kubectl -n default wait --for=condition=Ready pod/example --timeout=180s
