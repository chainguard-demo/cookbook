#!/bin/bash

set -euo pipefail

IMAGE="${1:?Must provide an image reference as the first argument}"
PLATFORM="${2:-linux/amd64}"

cosign download attestation \
  --platform="${PLATFORM}" \
  --predicate-type=https://spdx.dev/Document \
  "${IMAGE}" \
  | jq -r '.payload | @base64d | fromjson |
    # First, try to find certificates in the SBOM.
    [.predicate.packages[] |
      if ((.name | startswith("NIST-")) and .downloadLocation != "NOASSERTION") then
        [.name, .downloadLocation]
      else
        empty
      end
    ] as $nist_certs |
    # If there are no results then this is either not a FIPS image, or it
    # predates the inclusion of certs in the SBOM. To cover the latter case,
    # try and use hardcoded mappings.
    if ($nist_certs | length) > 0 then
      $nist_certs
    else
      [.predicate.packages[] |
        if .name == "openssl-provider-fips-3.1.2" and (.versionInfo | test("^3\\.1\\.2-r[0-4]$")) then
          ["NIST-CMVP-4985", "https://csrc.nist.gov/projects/cryptographic-module-validation-program/certificate/4985"]
        elif .name == "openssl-provider-fips" and (.versionInfo | test("^3\\.0\\.9-r[0-9]+$")) then
          ["NIST-CMVP-4856", "https://csrc.nist.gov/projects/cryptographic-module-validation-program/certificate/4856"]
        elif .name == "libcrypto3" and (.versionInfo | test("^(3\\.4\\.0-r([2-9]|[1-9][0-9]+)|3\\.4\\.[1-9][0-9]*(-r[0-9]+)?|3\\.([5-9]|[1-9][0-9]+)\\.[0-9]+(-r[0-9]+)?|([4-9]|[1-9][0-9]+)\\.[0-9]+\\.[0-9]+(-r[0-9]+)?)$")) then
          ["NIST-ESV-191", "https://csrc.nist.gov/projects/cryptographic-module-validation-program/entropy-validations/certificate/191"]
        elif .name == "bouncycastle-fips" and (.versionInfo | test("^2\\.1\\.[0-9]+-r[0-9]+$")) then
          ["NIST-CMVP-4943", "https://csrc.nist.gov/projects/cryptographic-module-validation-program/certificate/4943"]
        elif .name == "bouncycastle-fips" and (.versionInfo | test("^2\\.0\\.0-r[0-9]$")) then
          ["NIST-CMVP-4743", "https://csrc.nist.gov/projects/cryptographic-module-validation-program/certificate/4743"]
        elif (.name == "bouncycastle-fips-1.0") or (.name == "bouncycastle-fips" and (.versionInfo | test("^1\\.0\\.2-r[0-9]+$"))) then
          ["NIST-CMVP-4616", "https://csrc.nist.gov/projects/cryptographic-module-validation-program/certificate/4616"]
        elif .name == "bouncycastle-rng-jent" then
          ["NIST-ESV-266", "https://csrc.nist.gov/projects/cryptographic-module-validation-program/entropy-validations/certificate/266"]
        elif .name == "boringssl-fips-static-2023042800-tools" then
          ["NIST-CMVP-4953", "https://csrc.nist.gov/projects/cryptographic-module-validation-program/certificate/4953"]
        elif .name == "libgcrypt-al2023-fips" then
          ["NIST-CMVP-4971", "https://csrc.nist.gov/projects/cryptographic-module-validation-program/certificate/4971"]
        elif .name == "aws-lc-fips" then
          (["NIST-CMVP-4759", "https://csrc.nist.gov/projects/cryptographic-module-validation-program/certificate/4759"],  ["NIST-CMVP-4816", "https://csrc.nist.gov/projects/cryptographic-module-validation-program/certificate/4816"])
        else
          empty
        end
      ]
    end | unique | .[] | @tsv'
