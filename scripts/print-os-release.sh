#!/bin/bash

images=(
  "docker.io/curlimages/curl:8.7.1"
  "registry.k8s.io/ingress-nginx/controller:v1.11.2"
  "registry.k8s.io/defaultbackend-amd64:1.5"
)

echo "---------------------------------------------"

for IMAGE in "${images[@]}"; do
  os_name=$(docker run --rm --entrypoint sh "$IMAGE" -c "grep '^NAME=' /etc/os-release" 2>/dev/null | cut -d= -f2 | tr -d '"')
  if [ -z "$os_name" ]; then
    os_name="UNKNOWN"
  fi
  echo "$IMAGE $os_name"
done

echo "---------------------------------------------"
