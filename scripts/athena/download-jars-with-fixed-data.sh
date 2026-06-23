#!/bin/bash

echo "Fetching gavs endpoint"
curl -L --user "$CHAINGUARD_JAVA_IDENTITY_ID:$CHAINGUARD_JAVA_TOKEN" $BASEURL-/api/gavs 2>/dev/null | jq > gavs.json
echo "GAVs found: $(jq '.gavs | length' gavs.json)"
echo "Total fixes: $(jq '[.gavs[] | capture("cgr\\.(?<n>[0-9]+)") | .n | tonumber] | add // 0' gavs.json)"
mkdir -p json
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
      echo "Fixed version found: $group:$artifact:$fixed_version"
      JARURL="$BASEURL/${group//.//}/${artifact//.//}/$version/$artifact-$version.jar"
      echo "URL=$JARURL"
      curl -L --user "$CHAINGUARD_JAVA_IDENTITY_ID:$CHAINGUARD_JAVA_TOKEN" -O "$JARURL"
  else
      echo "No fixed version available: $name"
  fi
  echo "$QUERYJSON" > "json/$name"
done
