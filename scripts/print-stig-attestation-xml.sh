#!/usr/bin/env bash

IMAGE="cgr.dev/chainguard-private/jdk-fips:openjdk-17"

cosign download attestation "$IMAGE" 2>/dev/null |
  jq -r '.payload' |
  base64 -d |
  jq -r '
    select(.predicateType == "https://cosign.sigstore.dev/attestation/v1") |
    .predicate.Data |
    fromjson |
    .Data
  '
