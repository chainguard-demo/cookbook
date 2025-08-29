#!/bin/bash

set -euo pipefail

# Check we have the required tools installed to run the script
cmds="
  chainctl
  crane
  docker
  kind
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
if kind get clusters 2>/dev/null | grep -Eq '^filebeat$'; then
  kind delete cluster --name filebeat
fi

# Create the cluster
kind create cluster --name filebeat

# We'll write temporary artifacts to this location
tmp_dir=$(mktemp -d)
trap "rm -rf ${tmp_dir}" EXIT

# Add docker config to the kind node so it can pull images from cgr.dev
echo "Adding docker config to kind node..." >&2
mkdir -p "${tmp_dir}/docker"
export DOCKER_CONFIG="${tmp_dir}/docker"
crane auth login -u _token -p $(chainctl auth token --audience=cgr.dev) cgr.dev
docker cp "${DOCKER_CONFIG}/config.json" filebeat-control-plane:/var/lib/kubelet/config.json
docker exec filebeat-control-plane systemctl restart kubelet.service
