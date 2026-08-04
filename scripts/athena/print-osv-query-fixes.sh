#!/bin/bash

echo "Fetching gavs endpoint"
page_token=""
echo '{"gavs": []}' > gavs.json

while :; do
    if [ -n "$page_token" ]; then
        url="$BASEURL-/api/gavs?page_size=10000&page_token=$page_token"
    else
        url="$BASEURL-/api/gavs?page_size=10000"
    fi
    
    response=$(curl -L --user "$CHAINGUARD_JAVA_IDENTITY_ID:$CHAINGUARD_JAVA_TOKEN" "$url" 2>/dev/null)
    jq --argjson new "$(echo "$response" | jq '.gavs // []')" \
        '.gavs += $new' gavs.json > gavs.json.tmp && mv gavs.json.tmp gavs.json
    page_token=$(echo "$response" | jq -r '.next_page_token // empty')
    if [ -z "$page_token" ]; then
        break
    fi
done

echo "saving results to gavs.json"
echo "Unique artifacts (GAVs) found: $(jq '.gavs | length' gavs.json)"

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

# Build a deduped list of "group:artifact:baseversion" keys
gav_keys=$(jq -r '.gavs[]' gavs.json | while read -r gav; do
  group=$(echo "$gav" | cut -d: -f1)
  artifact=$(echo "$gav" | cut -d: -f2)
  version=$(echo "$gav" | cut -d: -f3)
  baseversion=$(echo "$version" | sed -E 's/\.cgp\.[0-9]+//')
  echo "${group}:${artifact}:${baseversion}"
done | sort -u)

while IFS=: read -r group artifact baseversion; do

  # echo "OSV Query: ${group}:${artifact}:${baseversion}"
  name="${group}:${artifact}"
  
  QUERYJSON=$(curl -s "$CONSOLE_API_URL_QUERY" \
       -H "Authorization: Bearer $(chainctl auth token)" \
       -H 'Content-Type: application/json' \
       -d "{\"package\":{\"ecosystem\":\"Maven\",\"name\":\"${name}\"}}" | jq)

  read -r fixed_version id < <(echo "$QUERYJSON" | jq -r '
    [.vulns[]
      | . as $v
      | ($v.affected[].ranges[].events[] | select(has("fixed")) | .fixed) as $f
      | "\($f)\t\($v.id)"
    ] | first // empty
  ' | tr '\t' ' ')

  if [ -n "$fixed_version" ]; then
      echo "Fix available for $id: Update $group:$artifact:$baseversion ==> $group:$artifact:$fixed_version "
  fi

done <<< "$gav_keys"
