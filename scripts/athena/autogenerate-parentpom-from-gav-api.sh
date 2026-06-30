#!/bin/bash
set -euo pipefail

export BASEURL="REDACTED"
# export BASEURL="https://chainguardlibraries.jfrog.io/artifactory/janani-test/"
export CONSOLE_API_URL_QUERY="REDACTED"
export CHAINGUARD_JAVA_IDENTITY_ID=REDACTED
export CHAINGUARD_JAVA_TOKEN=REDACTED


echo "Fetching gavs endpoint"
# -f makes curl fail on HTTP errors (401 etc) instead of writing an error body;
# save raw so a bad response isn't hidden by a jq parse error in a pipe.
curl -fsSL --user "$CHAINGUARD_JAVA_IDENTITY_ID:$CHAINGUARD_JAVA_TOKEN" \
  "$BASEURL-/api/gavs" -o gavs.json \
  || { echo "error: fetch failed (check token, identity id, BASEURL)" >&2; exit 1; }

# Guard: ensure we actually got a non-empty .gavs array before iterating.
if ! jq -e '(.gavs // []) | length > 0' gavs.json >/dev/null 2>&1; then
  echo "error: response has no non-empty .gavs array. First bytes:" >&2
  head -c 300 gavs.json >&2; echo >&2
  exit 1
fi

echo "GAVs found: $(jq '.gavs | length' gavs.json)"
echo "Total fixes: $(jq '[.gavs[] | capture("cgr\\.(?<n>[0-9]+)") | .n | tonumber] | add // 0' gavs.json)"

mkdir -p jars patches

# Collapse duplicate group:artifact to the highest version, since
# <dependencyManagement> allows only one version per coordinate.
deduped=$(jq -r '.gavs[]' gavs.json | sort -V | awk -F: '
  { k = $1 FS $2 }
  NR == 1 { kept = $0; pk = k; next }
  k == pk { print "  dropped duplicate: " kept > "/dev/stderr"; kept = $0; next }
  { print kept; kept = $0; pk = k }
  END { if (NR > 0) print kept }
')

# Build all dependency entries first.
deps=""
for gav in $deduped; do
  group=$(echo "$gav" | cut -d: -f1)
  artifact=$(echo "$gav" | cut -d: -f2)
  version=$(echo "$gav" | cut -d: -f3)

  deps="${deps}      <dependency>
        <groupId>${group}</groupId>
        <artifactId>${artifact}</artifactId>
        <version>${version}</version>
      </dependency>
"
done

# Write pom.xml once, with the dependencyManagement block assembled.
echo "Writing pom.xml"
cat > pom.xml <<***REMOVED***
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>

  <groupId>dev.chainguard</groupId>
  <artifactId>cgr-java-2e4b-overrides</artifactId>
  <version>1.0.0</version>
  <packaging>pom</packaging>

  <dependencyManagement>
    <dependencies>
${deps}    </dependencies>
  </dependencyManagement>
</project>
***REMOVED***

echo "Done: pom.xml written"
