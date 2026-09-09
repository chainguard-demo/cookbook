#!/bin/bash

echo ""
echo "Fetching Java Athena GAVs endpoint"
page_token=""
echo '{"gavs": []}' > javagavs.json

while :; do
    if [ -n "$page_token" ]; then
        url="$BASEURLJAVA-/api/gavs?page_size=10000&page_token=$page_token"
    else
        url="$BASEURLJAVA-/api/gavs?page_size=10000"
    fi
    
    response=$(curl -sL --user "$CHAINGUARD_JAVA_IDENTITY_ID:$CHAINGUARD_JAVA_TOKEN" "$url")
    jq --argjson new "$(echo "$response" | jq '.gavs // []')" \
        '.gavs += $new' javagavs.json > gavs.json.tmp && mv gavs.json.tmp javagavs.json    
    page_token=$(echo "$response" | jq -r '.next_page_token // empty')
    if [ -z "$page_token" ]; then
        break
    fi
done

echo "Saving results to javagavs.json"
echo "Unique Java Artifacts found: $(jq '.gavs | length' javagavs.json)"

echo ""
echo "Fetching Python Athena GAVs endpoint"
page_token=""
echo '{"packages": []}' > pypackages.json

while :; do
    if [ -n "$page_token" ]; then
        url="$BASEURLPYTHON-/api/packages?page_size=10000&page_token=$page_token"
    else
        url="$BASEURLPYTHON-/api/packages?page_size=10000"
    fi

    response=$(curl -sL --user "$CHAINGUARD_PYTHON_IDENTITY_ID:$CHAINGUARD_PYTHON_TOKEN" "$url")
    jq --argjson new "$(echo "$response" | jq '.packages // []')" \
        '.packages += $new' pypackages.json > pypackages.json.tmp && mv pypackages.json.tmp pypackages.json    
    
    page_token=$(echo "$response" | jq -r '.nextPageToken // empty')
    if [ -z "$page_token" ]; then
        break
    fi
done

echo "Saving results to pypackages.json"
echo "Unique Python Artifacts found: $(jq '.packages | length' pypackages.json) with $(jq '[.packages[].versionCount] | add' pypackages.json) versions"
echo ""
