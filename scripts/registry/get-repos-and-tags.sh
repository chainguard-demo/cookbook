#!/bin/bash

# cgr.dev/acme.com
if [ -z "${PRIVATEREPO}" ]; then
  export PRIVATEREPO="acme.com"  
fi

# From the pull token
if [ -z "${USERNAME}" ]; then
  export USERNAME=""
fi

# From the pull token
if [ -z "${PASSWORD}" ]; then
  export PASSWORD=""
fi

# Encode Basic Auth credentials
TOKEN=$(echo -n "${USERNAME}:${PASSWORD}" | base64 -w0)

# Get the list of repositories
repositories=$(curl -s -H "Authorization: Bearer $(curl -s -H "Authorization: Basic $TOKEN" "https://cgr.dev/token?scope=registry:catalog:*&service=cgr.dev" | jq -r .token)" "https://cgr.dev/v2/_catalog" | jq -r '.repositories[]')

for repo in $repositories; do
  echo "Getting tags for $repo"

  TAGSTOKEN=$(curl -s -H "Authorization: Basic $TOKEN" "https://cgr.dev/token?scope=repository:${repo}:pull" | jq -r .token)
  tags=$(curl -s -H "Authorization: Bearer ${TAGSTOKEN}" "https://cgr.dev/v2/${repo}/tags/list" | jq -r '.tags[]')

  for tag in $tags; do
    if [[ "$tag" != *"sha256"* ]]; then
      echo "$repo/$tag"
    fi
  done  
done
