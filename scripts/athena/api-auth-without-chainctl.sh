#!/bin/bash

# In this example I login to the Chainguard Console and using the OIDC integrations (Google in my case) and then use that OIDC token to programmatically make API calls
export CONSOLE_API_URL_QUERY="https://console-api.enforce.dev/argos/v1/osv/query"
export AUDIENCE="https://console-api.enforce.dev"
# I grabbed my identity from the output of $ chainctl auth status
# The identity can also be ontained through the console under settings
export IDENTITY=""
export PORT=8989

printf 'HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\nDone' | nc -l "$PORT" > /tmp/cg_callback &
xdg-open "https://issuer.enforce.dev/oauth?audience=https://console-api.enforce.dev&client_id=auth0&exit=redirect&skip_registration=true&redirect=http%3A%2F%2Flocalhost%3A${PORT}%2Fcallback%3Ftoken%3Dtrue"
sleep 5
export IDENTITY_TOKEN=$(grep -o 'token=[^& ]*' /tmp/cg_callback | grep -v 'token=true' | head -1 | cut -d= -f2)
echo "$IDENTITY_TOKEN"
export name="com.amazon.ion:ion-java"
echo "name=$name"
curl -s "$CONSOLE_API_URL_QUERY" \
       -H "Authorization: Bearer $IDENTITY_TOKEN" \
       -H 'Content-Type: application/json' \
       -d "{\"package\":{\"ecosystem\":\"Maven\",\"name\":\"${name}\"}}" | jq
