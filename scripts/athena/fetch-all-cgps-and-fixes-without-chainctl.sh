#!/bin/bash

set -euo pipefail

# In this example I login to the Chainguard Console and using the OIDC integrations (Google in my case) and then use that OIDC token to programmatically make API calls
export CONSOLE_API_URL_DUMP="https://console-api.enforce.dev/argos/v1/osv/dump"
export AUDIENCE="https://console-api.enforce.dev"
# I grabbed my identity from the output of $ chainctl auth status
# The identity can also be ontained through the console under settings
export IDENTITY="a79ad76794eb3869959effe72929836b37b34ecb"
export PORT=8989
export OSVFILE="osv-dump.tgz"
export STREAM="osv-dump.ndjson"
export OUTDIR="osv-records"

# In order to manually pull the token using a browser on any platform including Windows using Chrome:
# 1. Log in at console.chainguard.dev
# 2. Open Developer Tools on the console homepage
# 3. Go to Applications
# 4. Find the console.chainguard.dev => chainguard-session value (ex. under Cookies > https://console.chainguard.dev > chainguard-session)

# In order to automatically pull the chainguard-session from the browsesr using Linux run:
# printf 'HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\nDone' | nc -l "$PORT" > /tmp/cg_callback &
# xdg-open "https://issuer.enforce.dev/oauth?audience=https://console-api.enforce.dev&client_id=auth0&exit=redirect&skip_registration=true&redirect=http%3A%2F%2Flocalhost%3A${PORT}%2Fcallback%3Ftoken%3Dtrue"
# sleep 5
# export IDENTITY_TOKEN=$(grep -o 'token=[^& ]*' /tmp/cg_callback | grep -v 'token=true' | head -1 | cut -d= -f2)

# In order to automatically pull the chainguard-session from the browsesr using a Mac run:
# printf 'HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\nDone' | nc -l "$PORT" > /tmp/cg_callback &
# open "https://issuer.enforce.dev/oauth?audience=https://console-api.enforce.dev&client_id=auth0&exit=redirect&skip_registration=true&redirect=http%3A%2F%2Flocalhost%3A${PORT}%2Fcallback%3Ftoken%3Dtrue"
# sleep 5
# IDENTITY_TOKEN=$(grep -o 'token=[^& ]*' /tmp/cg_callback | grep -v 'token=true' | head -1 | cut -d= -f2)
# [ -n "$IDENTITY_TOKEN" ] || { echo "no token captured"; exit 1; }

if [ -z "${IDENTITY_TOKEN:-}" ]; then
  echo "Error: IDENTITY_TOKEN is not set" >&2
  echo "Running this script requires a Chainguard Session Token saved to the IDENTITY_TOKEN variable"
  echo "Please see comments on how to set this variable"
  exit 1
fi

# Note:
# This endpoint is not a plain file download
# - It is a server-streaming RPC exposd over JSON (the grpc-gateway/Connect style)
# - So instead of getting a .tgz we get a sequence of JSON messages, each wrapped in {"result": ...}
# - Each chunk is base64 encoded
# - After we get all the chunks we need to reassemble into a .tgz
curl -fsSL --output "$STREAM" -H "Authorization: Bearer $IDENTITY_TOKEN" "$CONSOLE_API_URL_DUMP"
python3 - "$STREAM" "$OSVFILE" <<'PY'
import base64, json, sys
src, dst = sys.argv[1], sys.argv[2]
dec = json.JSONDecoder()
data = open(src).read()
i, n = 0, len(data)
with open(dst, 'wb') as out:
    while i < n:
        while i < n and data[i].isspace():
            i += 1
        if i >= n:
            break
        msg, i = dec.raw_decode(data, i)
        r = msg.get('result', {})
        if 'chunk' in r:
            out.write(base64.b64decode(r['chunk']))
        elif 'metadata' in r:
            print('expecting', r['metadata']['size_bytes'], 'bytes,',
                  'sha256', r['metadata']['sha256'], file=sys.stderr)
PY

# 3. verify against the metadata, then unpack
shasum -a 256 "$OSVFILE"
mkdir -p "$OUTDIR" && tar xzf "$OSVFILE" -C "$OUTDIR"

find "$OUTDIR" -name '*.json' -print0 \
  | xargs -0 jq -r 'select(any(.affected[]?.ranges[]?.events[]?; has("fixed"))) | .id'

echo "Full OSV Dump Saved to $$OUTDIR"
echo "Run the following command to list only vulnerabilities with fixes"
cat <<'EOF'
find "$OUTDIR" -name '*.json' -print0 \
  | xargs -0 jq -r 'select(any(.affected[]?.ranges[]?.events[]?; has("fixed"))) | .id'
EOF
