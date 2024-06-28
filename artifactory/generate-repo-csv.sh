#!/bin/bash

# Check if the token and artifactory_url variables are set
if [ -z "$token" ] || [ -z "$artifactory_url" ]; then
    echo "Error: Both 'token' and 'artifactory_url' environment variables must be set."
    exit 1
fi

# Check if the repositories file argument is provided, otherwise default to 'repositories.txt'
if [ -n "$1" ]; then
    repositories_file="$1"
else
    repositories_file="repositories.txt"
fi

csvimageslistfile=$(mktemp --suffix=.csv)
echo "repo,path,sha256,created,modified,updated,properties,downloaded,downloads" > "$csvimageslistfile"

while IFS= read -r repo; do
    
    echo "Querying repository: $repo"
    echo ""

    output=$(curl -s -X POST -H "Authorization: Bearer $token" -H "Content-Type: text/plain" "$artifactory_url/api/search/aql" --data "items.find({\"repo\":{\"\$match\":\"$repo\"}}).include(\"repo\",\"path\",\"sha256\",\"created\",\"modified\",\"updated\",\"property.*\",\"stat.downloaded\",\"stat.downloads\")")
    json_output=$(echo "$output" | jq -c '.results[] | select(.properties != null and (.properties[] | select(.key == "docker.manifest.type" and .value == "application/vnd.oci.image.index.v1+json"))) | 
    {repo, path, sha256, created, modified, updated, properties: (.properties | map(.value) | join(";")), downloaded: .["stats"][0]["downloads"], downloads: .["stats"][0]["downloaded"]}')
    
    # Convert to CSV format and remove double quotes
    echo "$json_output" | jq -r '[.repo, .path, .sha256, .created, .modified, .updated, .properties, .downloads, .downloaded] | @csv' | sed 's/"//g' >> "$csvimageslistfile"
    
done < "$repositories_file"

echo "---------------------------------------------"
echo ""
cat "$csvimageslistfile"
echo ""
echo "---------------------------------------------"
echo ""
echo "CSV file with image data saved to: $csvimageslistfile"
echo ""
echo "---------------------------------------------"