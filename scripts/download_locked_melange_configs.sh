#!/usr/bin/env bash
set -euo pipefail

export IMAGE="cgr.dev/cgr-demo.com/jdk:openjdk-17"
export CHAINGUARD_ORG="cgr-demo.com"
export ARCH="x86_64"
export DLDIR="$(pwd)/locked-melange-configs"

# 1) Extract apk name-version-rX list from SPDX attestation (amd64 digests)
PACKAGES=$(
  crane manifest "$IMAGE" \
  | jq -r '.manifests[] | select(.platform.architecture=="amd64") | .digest' \
  | xargs -I {} cosign verify-attestation \
      --type=spdx \
      --certificate-oidc-issuer=https://issuer.enforce.dev \
      --certificate-identity-regexp="https://issuer.enforce.dev/(4cf15780a13a9b6576d8b357e6524554c8c12a18/c03040118377d88c|4cf15780a13a9b6576d8b357e6524554c8c12a18/ca93125e202f81f8)" \
      "$IMAGE@{}" 2> /dev/null \
  | jq -r .payload \
  | base64 -d \
  | jq '.predicate' \
  | jq -r '
      .packages[]
      | select(.externalRefs[]?.referenceCategory == "PACKAGE_MANAGER"
            or .externalRefs[]?.referenceCategory == "PACKAGE-MANAGER")
      | .externalRefs[]
      | select(
          (.referenceCategory == "PACKAGE_MANAGER"
          or .referenceCategory == "PACKAGE-MANAGER")
          and (.referenceLocator | startswith("pkg:apk/"))
        )
      | .referenceLocator
      | capture("^pkg:apk/[^/]+/(?<namever>[^?]+)")
      | .namever
      | capture("^(?<name>[^@]+)@(?<ver>.+)$")
      | "\(.name | gsub("%2[Bb]"; "+"))-\(.ver)"
    ' \
  | sort -u
)

echo ""
echo "Extracted the following packages:"
printf '%s\n' "$PACKAGES"
echo ""
echo "---------------------------------------------"
echo ""

# Extract the apk repository list (where we download the locked melange file)
REPOS=$(
  crane export "$IMAGE" - \
  | tar -Oxf - etc/apk/repositories \
  | sed -e 's/[[:space:]]*$//' -e '/^$/d' -e '/^[[:space:]]*#/d'
)

echo "Extracted the following apk repositories:"
printf '%s\n' "$REPOS"
echo "---------------------------------------------"

mkdir -p "$DLDIR"
echo ""
echo "Generating pull token"
echo "Organization: $CHAINGUARD_ORG"
chainctl auth pull-token --parent=${CHAINGUARD_ORG} -o json 2>/dev/null > /tmp/token.json
export IDENTITY=$(jq -r .identity_id /tmp/token.json)
export IDENTITY_TOKEN=$(jq -r .token /tmp/token.json)

echo "Granting the pull token identity the apk.pull role"
printf 'y\n' | chainctl iam role-bindings create \
  --parent="${CHAINGUARD_ORG}" \
  --identity="${IDENTITY}" \
  --role=apk.pull
  
echo "Extracting locked melange files for both public and private APKs..."

printf '%s\n' "$PACKAGES" | while IFS= read -r pkg; do
  [ -z "$pkg" ] && continue

  out="$DLDIR/${pkg}.apk.melange.yaml"
  found=0

  while IFS= read -r repo; do
    [ -z "$repo" ] && continue

    url="${repo%/}/${ARCH}/${pkg}.apk"    

    # Download APK and extract .melange.yaml
    if curl -fsSL "$url" 2>/dev/null \
      | tar --warning=no-unknown-keyword -Oxz .melange.yaml > "$out" 2>/dev/null; then
      echo "OK: $out"
      found=1
      break
    fi
  done <<< "$REPOS"

  if [ "$found" -eq 0 ]; then
    #If we are here then we could not pull the APK without auth so trying with auth to apk.cgr.dev (since virtualapk does not support pull token auth)
    if set -o pipefail; \
        curl -fsSL -u "${IDENTITY}:${IDENTITY_TOKEN}" "https://apk.cgr.dev/${CHAINGUARD_ORG}/${ARCH}/${pkg}.apk" 2>/dev/null \
            | tar --warning=no-unknown-keyword -Oxz .melange.yaml > "$out"; then
        echo "OK: $out"
    else
        echo "ERROR: failed to extract .melange.yaml from ${pkg}.apk" >&2
    fi
  fi
done

echo "Locked melanges files saved to $DLDIR"
