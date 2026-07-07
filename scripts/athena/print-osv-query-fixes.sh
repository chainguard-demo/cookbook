#!/bin/bash

echo "Fetching gavs endpoint"
curl -L --user "$CHAINGUARD_JAVA_IDENTITY_ID:$CHAINGUARD_JAVA_TOKEN" "$BASEURL-/api/gavs?page_size=1000" 2>/dev/null | jq > gavs.json
echo "GAVs found: $(jq '.gavs | length' gavs.json)"
echo "saving results to gavs.json"

echo ".cgp fixes: $(jq '
  [.gavs[] | . as $gav
    | capture("\\.cgp\\.(?<n>[0-9]+)") as $m
    | {
        base: ($gav | sub("\\.cgp\\.[0-9]+"; "")),
        n: ($m.n | tonumber)
      }
  ]
  | group_by(.base)
  | map(map(.n) | max)
  | add // 0
' gavs.json)"

mkdir -p jars patches
for gav in $(jq -r '.gavs[]' gavs.json); do
  
  group=$(echo "$gav" | cut -d: -f1)
  artifact=$(echo "$gav" | cut -d: -f2)
  version=$(echo "$gav" | cut -d: -f3)
  name="${group}:${artifact}"
  QUERYJSON=$(curl -s "$CONSOLE_API_URL_QUERY" \
       -H "Authorization: Bearer $(chainctl auth token)" \
       -H 'Content-Type: application/json' \
       -d "{\"package\":{\"ecosystem\":\"Maven\",\"name\":\"${name}\"}}" | jq)
  
  if fixed_version=$(echo "$QUERYJSON" | jq -r '.vulns[].affected[].ranges[].events[] | select(has("fixed")) | .fixed' | head -1) && [ -n "$fixed_version" ]; then
      echo "OSV Fixed Data Found for Artifact: $group:$artifact:$fixed_version"
  fi
done
