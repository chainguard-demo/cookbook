#!/bin/bash

# This script is used within a DMZ to pull images from a private Chainguard registry, then do common ingestion work, and push them to an internal registry.

# image source (upstream)
UPSTREAM_REGISTRY="cgr.dev/some-natalie.dev/"
# image list (name:tag, newline separated)
IMAGE_LIST="image-list.txt"
# image destination (downstream)
DOWNSTREAM_REGISTRY="ghcr.io/some-natalie/chainguard-canned/"
# scan failure threshold (will not fail on vulnerabilities at all if not set, will fail on medium or higher if set to medium, etc.)
# options=[negligible low medium high critical]
SCAN_FAILURE_THRESHOLD=""

# check for requirements (docker, grype, syft, cosign, jq, incert)
requirements=(docker grype syft cosign jq incert)
for requirement in "${requirements[@]}"; do
    if ! command -v $requirement &> /dev/null
    then
        echo "$requirement could not be found in \$PATH, please install it."
        exit 1
    fi
done

# check for image list
if [ ! -f $IMAGE_LIST ]; then
    echo "Image list not found, please create a file named $IMAGE_LIST with a list of images to process."
    exit 1
fi

# read image list
declare -a images
while IFS= read -r image; do
    images+=("$image")
done < $IMAGE_LIST

# for each image
#   pull from private registry
pull_image() {
    echo "Pulling $UPSTREAM_REGISTRY$image" >> $image-log.txt
    docker pull $UPSTREAM_REGISTRY$image
}

#   scan with grype, optionally fail if medium or higher vulnerabilities found
scan_image() {
    echo "Scanning $UPSTREAM_REGISTRY$image" >> $image-log.txt
    if [ -z $SCAN_FAILURE_THRESHOLD ]; then
        grype $UPSTREAM_REGISTRY$image >> $image-log.txt
    else
        grype --fail-on $SCAN_FAILURE_THRESHOLD $UPSTREAM_REGISTRY$image >> $image-log.txt
    fi
}

#   verify attestation
verify_attestation() {
    echo "Verifying attestation for $UPSTREAM_REGISTRY$image"
    echo "The following checks were performed on each of these signatures:"
    echo "  - The cosign claims were validated"
    echo "  - Existence of the claims in the transparency log was verified offline"
    echo "  - The code-signing certificate was verified using trusted certificate authority certificates"
    cosign verify \
        --certificate-oidc-issuer=https://token.actions.githubusercontent.com \
        --certificate-identity=https://github.com/chainguard-images/images-private/.github/workflows/release.yaml@refs/heads/main \
    $UPSTREAM_REGISTRY/$image | jq >> $image-log.txt
}

#   download SBOM
download_sbom() {
    echo "Downloading SBOM for $UPSTREAM_REGISTRY$image"
    cosign download attestation $UPSTREAM_REGISTRY$image | jq -r .payload | base64 -d | jq .predicate > $image-sbom.json
}

#   add internal CA cert and push
run_incert() {
    echo "Adding internal CA cert to $UPSTREAM_REGISTRY$image"
    incert \
      -ca-certs-file test.crt \
      -image-url $UPSTREAM_REGISTRY$image \
      -dest-image-url $DOWNSTREAM_REGISTRY$image
}

echo "Processing ${#images[@]} images from $IMAGE_LIST"

for image in "${images[@]}"; do
    # pull from private registry
    echo "Pulling $UPSTREAM_REGISTRY$image"
    pull_image
    scan_image
    verify_attestation
    download_sbom
    run_incert
done
