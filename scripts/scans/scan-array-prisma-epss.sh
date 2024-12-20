#!/bin/bash

images=(
  "registry.access.redhat.com/ubi9/openjdk-21:1.17-2.1705482269"
  "registry.access.redhat.com/ubi9/openjdk-17:1.13-9.1665068440"
  "registry.access.redhat.com/ubi9/openjdk-11:1.13-7.1665068445"
  "registry.access.redhat.com/ubi8/openjdk-8:1.3-2.1591609345"
  "registry.access.redhat.com/ubi9/openjdk-21-runtime:1.17-2.1705482271"
  "registry.access.redhat.com/ubi9/openjdk-17-runtime:1.13-8.1665068444"
  "registry.access.redhat.com/ubi9/openjdk-11-runtime:1.13-5.1665068447"
  "registry.access.redhat.com/ubi8/openjdk-8-runtime:1.9-1.1622550104"
)

echo ""
echo "Image Size On Disk:"
    
# Loop through each item and append ":latest" if no tag is present
for i in "${!images[@]}"; do
    if [[ "${images[i]}" != *:* ]]; then
        images[i]="${images[i]}:latest"
    fi
    
    origimagestr="${images[i]}"
    
    # Pull the image and check for errors
    if docker pull "${images[i]}" 2>&1 | grep -iq "error"; then
      echo "Error encountered while pulling ${images[i]}. Exiting..."
      exit 1
    fi

    images[i]=$(docker inspect "${images[i]}" | jq -r '.[0].RepoDigests[0]')
    size=$(docker inspect "${images[i]}" | jq -r '.[0].Size // 0')
    size_mb=$(echo "scale=2; $size / 1024 / 1024" | bc)
    created=$(crane config "${images[i]}" | jq -r '.created | split("T")[0]')
    echo "$origimagestr,$size_mb,$created"

done

echo "---------------------------------------------"

echo "Scanning images..."
twistcli_scan_results=""
csv_output="scan_results.csv"
declare -A cve_epss_map
echo "Image,CVE ID,Severity" > "$csv_output"

for IMAGE in "${images[@]}"; do
  twistcli images scan --address=https://us-east1.cloud.twistlock.com/us-1-113031256 --token=$PRISMATOKEN --output-file=scans.json "$IMAGE" >/dev/null 2>&1
  cat scans.json | jq -r --arg image "$IMAGE" '.results[]?.vulnerabilities? // [] | .[] | [.id, .severity] | @csv' | while IFS=, read -r cve severity; do
    if [[ -z "${cve_epss_map[$cve]}" ]]; then
      
      # Remove the quotes around CVE ID because they make the curl not work
      cve=$(echo "$cve" | sed 's/^"\(.*\)"$/\1/')
      URL="https://api.first.org/data/v1/epss?cve="
      URL+=$cve
      URL+="&pretty=true"
      epss="$(curl -s -X 'GET' -H 'accept: application/json' $URL | jq -r '.data[].epss')"      
      if [[ -n "$epss" ]]; then
        cve_epss_map["$cve"]=$epss
      else
        cve_epss_map["$cve"]=""
      fi
    else
      epss=${cve_epss_map["$cve"]}
    fi

    echo "$IMAGE,$cve,$severity,$epss" >> "$csv_output"
  done
  sleep 2

done
echo "Scan results:"
cat "$csv_output"
echo "---------------------------------------------"
