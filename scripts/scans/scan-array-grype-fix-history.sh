#!/bin/bash

images=(
  "cgr.dev/chainguard-private/python:3.13.0"
)

# Repos and arch used to fetch .apk files for builddate lookups.
# Chainguard repo (authenticated) is tried first; Wolfi (public) on 404.
CGR_APK_REPO="https://apk.cgr.dev/chainguard"
WOLFI_APK_REPO="https://packages.wolfi.dev/os"
APK_ARCH="x86_64"

echo ""
echo "Image Size On Disk:"

for i in "${!images[@]}"; do
    [[ "${images[i]}" != *:* ]] && images[i]="${images[i]}:latest"
    origimagestr="${images[i]}"

    if docker pull "${images[i]}" 2>&1 | grep -iq "error"; then
        echo "Error encountered while pulling ${images[i]}. Exiting..."
        exit 1
    fi

    # One inspect call for both digest and size
    read -r digest size < <(docker inspect "${images[i]}" | jq -r '.[0] | "\(.RepoDigests[0]) \(.Size // 0)"')
    images[i]="$digest"
    size_mb=$(echo "scale=2; $size / 1024 / 1024" | bc)
    created=$(crane config "$digest" | jq -r '.created | split("T")[0]')
    echo "$origimagestr,$size_mb,$created"
done

echo "---------------------------------------------"

csv_output="scan_results.csv"

echo "Scanning images..."
header="id,severity,NVD_Publication_Date,state,chainguard_package,fix_versions,fixed_date"
echo "$header"
echo "$header" > "$csv_output"

# Auth token for apk.cgr.dev, fetched once
apk_token=$(chainctl auth token --audience apk.cgr.dev)
if [[ -z "$apk_token" ]]; then
    echo "ERROR: 'chainctl auth token --audience apk.cgr.dev' returned nothing." >&2
    echo "       Run 'chainctl auth login' and try again. Exiting..." >&2
    exit 1
fi

# Caches. NOTE: these functions return results via globals (pub_date /
# fixed_date_result) rather than echo/$(...), because command substitution
# runs in a subshell where cache writes would be lost.
declare -A nvd_cache
declare -A builddate_cache

# Fetch NVD publication date (with retries, rate-limit pacing, and caching).
# Result in global: pub_date
get_nvd_pub_date() {
    local cve_id="$1"
    pub_date=""

    if [[ -n "${nvd_cache[$cve_id]+x}" ]]; then
        pub_date="${nvd_cache[$cve_id]}"
        return
    fi

    local api_url="$NVD_BASE_URL?cveId=$cve_id"
    local attempt response http_code body

    for attempt in 1 2 3; do
        response=$(curl -s -w $'\n%{http_code}' -H "apiKey: $NVD_API_KEY" "$api_url")
        http_code=${response##*$'\n'}
        body=${response%$'\n'*}

        if [[ "$http_code" == "200" ]]; then
            pub_date=$(echo "$body" | jq -r '.vulnerabilities[0].cve.published // empty | split("T")[0]' 2>/dev/null)
            [[ -z "$pub_date" ]] && echo "  WARN: $cve_id not found in NVD" >&2
            break
        fi

        echo "  WARN: NVD lookup for $cve_id returned HTTP $http_code (attempt $attempt/3)" >&2
        sleep $((attempt * 5))
    done

    # Stay under NVD's rate limit (~50 requests / 30s with an API key)
    sleep 0.7

    nvd_cache[$cve_id]="$pub_date"
}

# Print an error message for a failed builddate lookup.
# Usage: troubleshoot_lookup <spec> <repo> <url> [curl auth args...]
troubleshoot_lookup() {
    local spec="$1" repo="$2" url="$3"
    shift 3
    local http_code
    http_code=$(curl -o /dev/null -sL "$@" -w '%{http_code}' "$url")
    if [[ "$http_code" == "404" ]]; then
        echo "  ERROR: $spec not found in $repo (HTTP 404)" >&2
    else
        echo "  ERROR: builddate lookup for $spec failed (HTTP $http_code from $url)" >&2
    fi
}

# Fetch the builddate of <pkg_name>-<pkg_version>.apk, trying CGR_APK_REPO
# first and falling back to WOLFI_APK_REPO on 404. Cached; troubleshoots
# when both lookups fail.
# Result in global: fixed_date_result (YYYY-MM-DD or empty)
get_fixed_date() {
    local pkg_name="$1" pkg_version="$2"
    local spec="${pkg_name}=${pkg_version}"
    fixed_date_result=""

    if [[ -n "${builddate_cache[$spec]+x}" ]]; then
        fixed_date_result="${builddate_cache[$spec]}"
        return
    fi

    local builddateraw builddateformatted="" url http_code

    # 1) Chainguard repo (authenticated)
    url="${CGR_APK_REPO%/}/${APK_ARCH}/${pkg_name}-${pkg_version}.apk"
    builddateraw=$(curl -sL --user "user:$apk_token" "$url" | tar -Oxz .PKGINFO 2>/dev/null | awk -F' = ' '/^builddate/ {print $2}')

    if [[ -z "$builddateraw" ]]; then
        http_code=$(curl -o /dev/null -sL --user "user:$apk_token" -w '%{http_code}' "$url")
        if [[ "$http_code" == "404" ]]; then
            # 2) Fall back to Wolfi repo (public, no auth)
            url="${WOLFI_APK_REPO%/}/${APK_ARCH}/${pkg_name}-${pkg_version}.apk"
            builddateraw=$(curl -sL "$url" | tar -Oxz .PKGINFO 2>/dev/null | awk -F' = ' '/^builddate/ {print $2}')
            if [[ -z "$builddateraw" ]]; then
                troubleshoot_lookup "$spec" "$WOLFI_APK_REPO" "$url"
            fi
        else
            troubleshoot_lookup "$spec" "$CGR_APK_REPO" "$url" --user "user:$apk_token"
        fi
    fi

    [[ -n "$builddateraw" ]] && builddateformatted=$(date -u -d @"$builddateraw" +%Y-%m-%d)
    fixed_date_result="$builddateformatted"

    builddate_cache[$spec]="$fixed_date_result"
}

for IMAGE in "${images[@]}"; do
    echo "Scanning: $IMAGE"

    # Tab-separated fields: id, severity, state, chainguard_package,
    # fix_versions, apk_name (apk_name is a helper, dropped from output)
    mapfile -t lines < <(grype "$IMAGE" -o json 2>/dev/null | jq -r '
    .matches[]
    | .vulnerability as $vuln
    | .artifact as $artifact
    | ((.relatedVulnerabilities // []) | map(select(.id | startswith("CVE-"))) | .[0].id) as $cve_id
    | [
        (if ($vuln.id | startswith("GHSA")) and ($cve_id != null) then $cve_id else $vuln.id end),
        $vuln.severity,
        ($vuln.fix.state // ""),
        ($artifact.metadata.originPackage // $artifact.name // ""),
        (($vuln.fix.versions // []) | join(" ")),
        (if $artifact.type == "apk" then ($artifact.name // "") else "" end)
      ]
    | @tsv')

    while IFS=$'\t' read -r id severity state pkg versions apk_name; do
        [[ "$id" != CVE-* ]] && continue

        get_nvd_pub_date "$id"   # sets: pub_date

        fixed_date=""
        if [[ -n "$apk_name" ]]; then
            for v in $versions; do
                get_fixed_date "$apk_name" "$v"   # sets: fixed_date_result
                d="$fixed_date_result"
                [[ -n "$d" && " $fixed_date " != *" $d "* ]] && fixed_date="${fixed_date:+$fixed_date }$d"
            done
        fi

        new_line="\"$id\",\"$severity\",$pub_date,\"$state\",\"$pkg\",\"$versions\",$fixed_date"
        echo "$new_line"
        echo "$new_line" >> "$csv_output"
    done < <(printf '%s\n' "${lines[@]}")
done

echo "---------------------------------------------"
