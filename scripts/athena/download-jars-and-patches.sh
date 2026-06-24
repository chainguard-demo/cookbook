#!/bin/bash

export BASEURL="REDACTED"
export CONSOLE_API_URL_QUERY="REDACTED"
export CHAINGUARD_JAVA_IDENTITY_ID=REDACTED
export CHAINGUARD_JAVA_TOKEN=REDACTED

echo "Fetching gavs endpoint"
curl -L --user "$CHAINGUARD_JAVA_IDENTITY_ID:$CHAINGUARD_JAVA_TOKEN" $BASEURL-/api/gavs 2>/dev/null | jq > gavs.json
echo "GAVs found: $(jq '.gavs | length' gavs.json)"
echo "Total fixes: $(jq '[.gavs[] | capture("cgr\\.(?<n>[0-9]+)") | .n | tonumber] | add // 0' gavs.json)"
echo "saving results to gavs.json"

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
  
  JARURL="$BASEURL${group//.//}/${artifact//.//}/$version/$artifact-$version.jar"
  PATCHURL="$BASEURL${group//.//}/${artifact//.//}/$version/$artifact-$version-patches.zip"
  
  JAR_URL_HTTP_CODE=$(curl -L --user "$CHAINGUARD_JAVA_IDENTITY_ID:$CHAINGUARD_JAVA_TOKEN" -s -o "jars/$(basename "$JARURL")" -w "%{http_code}" "$JARURL")
  [ "$JAR_URL_HTTP_CODE" = "200" ] && echo "Success: $JARURL" || echo "Failed ($JAR_URL_HTTP_CODE): $JARURL"
  
  PATCH_URL_HTTP_CODE=$(curl -L --user "$CHAINGUARD_JAVA_IDENTITY_ID:$CHAINGUARD_JAVA_TOKEN" -s -o "patches/$(basename "$PATCHURL")" -w "%{http_code}" "$PATCHURL")
  [ "$PATCH_URL_HTTP_CODE" = "200" ] && echo "Success: $PATCHURL" || echo "Failed ($PATCH_URL_HTTP_CODE): $PATCHURL"
done
