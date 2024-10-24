#!/bin/bash

# Default scanner is 'grype'
scanner="grype"

# Default scanner is 'grype'
scanner="grype"

# Check if --scanner option is provided
if [[ "$1" == "--scanner=trivy" ]]; then
    scanner="trivy"
elif [[ "$1" == "--scanner=grype" ]]; then
    scanner="grype"
elif [[ -n "$1" ]]; then
    echo "Unknown option: $1"
    exit 1
fi

images=(
  "openjdk:21-jdk"
  "openjdk:17-jdk"
  "openjdk:11-jdk"
  "openjdk:8-jdk"
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

    echo "$origimagestr: $size_mb MB"

done

echo "---------------------------------------------"

json='{"items":[]}'
totalCritical=0
totalHigh=0
totalMedium=0
totalLow=0
totalWontFix=0
totalCount=0

echo "Scanning images..."
for image in "${!image_digests[@]}"; do
    echo "Image: $image, Digest: ${image_digests[$image]}, "
done

for IMAGE in "${images[@]}"; do
  
  if [[ "$scanner" == "grype" ]]; then
    # Grype
    output=$(grype $IMAGE -o json 2>/dev/null | jq -c '{Total: [.matches[].vulnerability] | length, Critical: [.matches[] | select(.vulnerability.severity == "Critical")] | length, High: [.matches[] | select(.vulnerability.severity == "High")] | length, Medium: [.matches[] | select(.vulnerability.severity == "Medium")] | length, Low: [.matches[] | select(.vulnerability.severity == "Low")] | length, WontFix: [.matches[] | select(.vulnerability.fix.state == "wont-fix")] | length }')
    critical=$(jq '.Critical' <<< "$output")
    high=$(jq '.High' <<< "$output")
    medium=$(jq '.Medium' <<< "$output")
    low=$(jq '.Low' <<< "$output")
    wontfix=$(jq '.WontFix' <<< "$output")
    total=$(jq '.Total' <<< "$output")
  
  elif [[ "$scanner" == "trivy" ]]; then
    # Trivy
    output=$(trivy image -f json "$IMAGE" 2>/dev/null | jq -c 'if (.Results | length) == 0 then { Total: 0, Critical: 0, High: 0, Medium: 0, Low: 0, WontFix: 0 } else [.Results[] | select(has("Vulnerabilities")) | .Vulnerabilities[]] | { Total: length, Critical: (map(select(.Severity == "CRITICAL")) | length), High: (map(select(.Severity == "HIGH")) | length), Medium: (map(select(.Severity == "MEDIUM")) | length), Low: (map(select(.Severity == "LOW")) | length), WontFix: (map(select(.Status == "will_not_fix")) | length)} end')
    critical=$(jq '.Critical' <<< "$output")
    high=$(jq '.High' <<< "$output")
    medium=$(jq '.Medium' <<< "$output")
    low=$(jq '.Low' <<< "$output")
    wontfix=$(jq '.WontFix' <<< "$output")
    total=$(jq '.Total' <<< "$output")
  fi
  
  echo "$output"
  json=$(jq --arg image "$IMAGE" \
          --arg critical "$critical" \
          --arg high "$high" \
          --arg medium "$medium" \
          --arg low "$low" \
          --arg wontfix "$wontfix" \
          --arg total "$total" \
          '.items += [{
            image: $image,
            scan: {
              type: "grype",
              critical: ($critical | tonumber),
              high: ($high | tonumber),
              medium: ($medium | tonumber),
              low: ($low | tonumber),
              wontfix: ($wontfix | tonumber),
              total: ($total | tonumber)
            }
          }]' <<< "$json")


  totalCritical=$((totalCritical + critical))
  totalHigh=$((totalHigh + high))
  totalMedium=$((totalMedium + medium))
  totalLow=$((totalLow + low))
  totalWontFix=$((totalWontFix + wontfix))
  totalCount=$((totalCount + total))

done
echo "---------------------------------------------"

# Calculate averages
averageCritical=$((totalCritical / ${#images[@]}))
averageHigh=$((totalHigh / ${#images[@]}))
averageMedium=$((totalMedium / ${#images[@]}))
averageLow=$((totalLow / ${#images[@]}))
averageWontFix=$((totalWontFix / ${#images[@]}))

# Display totals and averages
echo "Total Vulnerabilities: $totalCount"
echo "Total Critcal CVEs: $totalCritical"
echo "Total High CVEs: $totalHigh"
echo "Total Medium CVEs: $totalMedium"
echo "Total Low CVEs: $totalLow"
echo -n "Average Vulnerabilities: "; echo "scale=2; $totalCount / ${#images[@]}" | bc
echo -n "Average Critcal CVEs: "; echo "scale=2; $totalCritical / ${#images[@]}" | bc
echo -n "Average High CVEs: "; echo "scale=2; $totalHigh / ${#images[@]}" | bc
echo -n "Average Medium CVEs: "; echo "scale=2; $totalMedium / ${#images[@]}" | bc
echo -n "Average Low CVEs: "; echo "scale=2; $totalLow / ${#images[@]}" | bc

echo "JSON Output:"
echo "$json"
echo "CSV Output:"
echo "$json" | jq -r '.items[] | [.image, .scan.total, .scan.critical, .scan.high, .scan.medium, .scan.low, .scan.wontfix] | @csv'
