#!/bin/bash

set -euo pipefail

# Validate argument
if [[ ! "${1}" =~ ^cgr\.dev/([^/]+)/([^/]+)(:.+)?$ ]]; then
  echo "Error: image must be of the form cgr.dev/{ORG}/{IMAGE_NAME}:{TAG}" >&2
  exit 1
fi

# Extract org from image reference
org="${BASH_REMATCH[1]}"

# Resolve the image reference to digest so we're always operating on the same
# image
img=$(crane digest --full-ref --platform=linux/amd64 "${1}")

# Find the main package name from the labels
main_package=$(crane config "${img}" | jq -r '.config.Labels["dev.chainguard.package.main"]')

echo "Image:        ${img}"
echo "Main package: ${main_package}"

# Get the version of the main package from the apko image-configuration attestation
main_package_version=$(
  cosign download attestation \
    --predicate-type=https://apko.dev/image-configuration \
    "${img}" \
    | jq -r --arg pkg "${main_package}" \
        '.payload | @base64d | fromjson | .predicate.contents.packages[]
         | select(startswith($pkg + "="))
         | split("=")[1]'
)

echo "Version:      ${main_package_version}"

# Find the APK in apk.cgr.dev/chainguard, apk.cgr.dev/extra-packages, or apk.cgr.dev/${org}
apk_url=""
apk_curl_opts=()
for repo in chainguard extra-packages "${org}"; do
  candidate="https://apk.cgr.dev/${repo}/x86_64/${main_package}-${main_package_version}.apk"
  if [[ "${repo}" == "${org}" ]]; then
    token=$(chainctl auth token --audience=apk.cgr.dev)
    curl_opts=(-H "Authorization: Bearer ${token}")
  else
    curl_opts=()
  fi
  if curl -sfI "${curl_opts[@]+"${curl_opts[@]}"}" "${candidate}" >/dev/null 2>&1; then
    apk_url="${candidate}"
    apk_curl_opts=("${curl_opts[@]+"${curl_opts[@]}"}")
    echo "APK:          ${apk_url}"
    break
  fi
done

if [[ -z "${apk_url}" ]]; then
  echo "Error: could not find ${main_package}-${main_package_version}.apk in apk.cgr.dev" >&2
  exit 1
fi

# Extract the melange config from the APK and find the source
melange_yaml=$(curl -sL "${apk_curl_opts[@]+"${apk_curl_opts[@]}"}" "${apk_url}" | tar -Oxz .melange.yaml)

# Look for a fetch step (tarball source)
fetch_uri=$(echo "${melange_yaml}" | yq '.pipeline[] | select(.uses == "fetch") | .with.uri' 2>/dev/null | grep -v '^null$' | head -1 || true)

# Look for a git-checkout step (git source)
git_repo=$(echo "${melange_yaml}" | yq '.pipeline[] | select(.uses == "git-checkout") | .with.repository' 2>/dev/null | grep -v '^null$' | head -1 || true)
git_tag=$(echo "${melange_yaml}" | yq '.pipeline[] | select(.uses == "git-checkout") | .with.tag' 2>/dev/null | grep -v '^null$' | head -1 || true)
git_commit=$(echo "${melange_yaml}" | yq '.pipeline[] | select(.uses == "git-checkout") | .with."expected-commit"' 2>/dev/null | grep -v '^null$' | head -1 || true)

# Print the source
if [[ -n "${fetch_uri}" ]]; then
  echo "Source:       ${fetch_uri}"
elif [[ -n "${git_repo}" ]]; then
  echo "Source:       ${git_repo}"
  [[ -n "${git_tag}" ]] && echo "Tag:          ${git_tag}"
  [[ -n "${git_commit}" ]] && echo "Commit:       ${git_commit}"
else
  echo "Source:       (not found in melange pipeline)"
fi
