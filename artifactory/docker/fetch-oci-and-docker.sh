#!/bin/bash

# Check if the token and artifactory_url variables are set
if [ -z "$token" ] || [ -z "$artifactory_url" ]; then
    echo "Error: Both 'token' and 'artifactory_url' environment variables must be set."
    exit 1
fi

output_file=${1:-repositories.txt}

# Step 1: Fetch repository names
reponames=$(curl -s -X POST -H "Authorization: Bearer $token" -H "Content-Type: text/plain" "$artifactory_url/api/search/aql" --data 'items.find().include("repo")' | jq -r '.results[].repo')
# reponames=$(curl -s -X POST -H "Authorization: Bearer $token" -H "Content-Type: text/plain" "$artifactory_url/api/search/aql" --data 'items.find({"repo": "cgr-pov", "type": "file", "name": {"$match": "manifest.json"}}).include("repo", "path", "name")' | jq -r '.results[] | "\(.repo)/\(.path)"')
# curl -s -H "Authorization: Bearer $token" "$artifactory_url/api/docker/cgr-pov/v2/_catalog" | jq .
# curl -s -H "Authorization: Bearer $token" "$artifactory_url/api/docker/cgr-pov/v2/go/tags/list" | jq .

echo ""
echo "The following repo names have been save to $output_file:"
echo ""
echo "$reponames" > $output_file
echo "$reponames"
