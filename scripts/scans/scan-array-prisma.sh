#!/bin/bash

images=(
  "cgr.dev/chainguard-private/node:24.0.0"
  "cgr.dev/chainguard-private/node:23.11.1"
  "cgr.dev/chainguard-private/node:22.6.0"
  "cgr.dev/chainguard-private/node:20.17.0"
  "cgr.dev/chainguard-private/dotnet-runtime:9.0.0"
  "cgr.dev/chainguard-private/aspnet-runtime:9.0.0"
  "cgr.dev/chainguard-private/dotnet-sdk:9.0.0"
  "cgr.dev/chainguard-private/dotnet-runtime:8.0.8"
  "cgr.dev/chainguard-private/aspnet-runtime:8.0.8"
  "cgr.dev/chainguard-private/dotnet-sdk:8.0.8"
  "cgr.dev/chainguard-private/dotnet-runtime:6.0"
  "cgr.dev/chainguard-private/aspnet-runtime:6.0"
  "cgr.dev/chainguard-private/dotnet-sdk:6.0.133"
  "cgr.dev/chainguard-private/nginx:1.26.2-r0"
  "cgr.dev/chainguard-private/nginx:1.27.1"
  "cgr.dev/chainguard-private/jdk:openjdk-17.0.13-r0"
  "cgr.dev/chainguard-private/jdk:openjdk-21.0.5-r0"
  "cgr.dev/chainguard-private/jdk:openjdk-24-r0-ea"
  "cgr.dev/chainguard-private/jdk:openjdk-23.0.1-r0"
  "cgr.dev/chainguard-private/python:3.11.10"
  "cgr.dev/chainguard-private/python:3.13.0-r0"
  "cgr.dev/chainguard-private/python:3.14.0-r2"
  "cgr.dev/chainguard-private/argocd:2.9.2"
  "cgr.dev/chainguard-private/istio-pilot:1.22.4-r0"
  "cgr.dev/chainguard-private/istio-pilot:1.24.0"
  "cgr.dev/chainguard-private/istio-proxy:1.22.4-r1"
  "cgr.dev/chainguard-private/istio-proxy:1.24.0"
)
   
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

    # images[i]=$(docker inspect "${images[i]}" | jq -r '.[0].RepoDigests[0]')
    # size=$(docker inspect "${images[i]}" | jq -r '.[0].Size // 0')
    # size_mb=$(echo "scale=2; $size / 1024 / 1024" | bc)
    # created=$(crane config "${images[i]}" | jq -r '.created | split("T")[0]')

done

echo "Scanning images..."
echo "image,created,total,critical,high,medium,low,other"

for IMAGE in "${images[@]}"; do
  
  #init
  json='{"items":[]}'
  : > scans.json
  
  created=$(crane config "$IMAGE" | jq -r '.created | split("T")[0]')  
  twistcli images scan --address=https://us-east1.cloud.twistlock.com/us-1-113031256 --token=$PRISMATOKEN --output-file=scans.json "$IMAGE" >/dev/null 2>&1
  
  output=$(jq -r '
  .results[].vulnerabilities as $vulns
  | reduce $vulns[].severity as $s (
      {critical:0,high:0,medium:0,low:0,other:0};
      .[
        (if $s=="critical" then "critical"
         elif $s=="high" then "high"
         elif $s=="medium" then "medium"
         elif $s=="low" then "low"
         else "other" end)
      ] += 1
    )
  | .total = ($vulns | length)
  | [.total, .critical, .high, .medium, .low, .other]
  | @csv
' scans.json)

echo "$IMAGE,$created,$output"

  # output=$(cat scans.json | jq -c '{
  #   Total: [.results[].vulnerabilities length,
  #   Critical: [.results[] | select(.vulnerabilities.severity == "critical")] | length,
  #   High: [.results[] | select(.vulnerabilities.severity == "high")] | length,
  #   Medium: [.results[] | select(.vulnerabilities.severity == "medium")] | length,
  #   Low: [.results[] | select(.vulnerabilities.severity == "low")] | length
  # }')

  # critical=$(jq '.Critical' <<< "$output")
  # high=$(jq '.High' <<< "$output")
  # medium=$(jq '.Medium' <<< "$output")
  # low=$(jq '.Low' <<< "$output")
  # total=$(jq '.Total' <<< "$output")

  # json=$(jq --arg image "$IMAGE" \
  #   --arg created "$created" \
  #   --arg critical "$critical" \
  #   --arg high "$high" \
  #   --arg medium "$medium" \
  #   --arg low "$low" \
  #   --arg total "$total" \
  #   '.items += [{
  #     image: $image,
  #     created: $created,
  #     scan: {
  #       type: "Prisma",
  #       critical: ($critical | tonumber),
  #       high: ($high | tonumber),
  #       medium: ($medium | tonumber),
  #       low: ($low | tonumber),
  #       total: ($total | tonumber)
  #     }
  #   }]' <<< "$json")
  # echo "$json" | jq -r '.items[] | [.image, .created, .scan.total, .scan.critical, .scan.high, .scan.medium, .scan.low] | @csv'  
done
echo "---------------------------------------------"
