#!/usr/bin/env bash
# change IMAGE to the image url that requires Stig report

IMAGE="cgr.dev/complyadvantage.com/python-fips:latest"
REPO="${IMAGE%%:*}"
BASE_DIGEST="$(crane manifest "$IMAGE" | jq -er '.annotations["org.opencontainers.image.base.digest"]')"

echo "base digest: $BASE_DIGEST" >&2

cosign download attestation "${REPO}@${BASE_DIGEST}" \
  | jq -r '.payload' \
  | base64 -d \
  | jq -er '
      select(.predicateType == "https://cosign.sigstore.dev/attestation/v1")
      | .predicate.Data
      | fromjson
      | .Data
    '
