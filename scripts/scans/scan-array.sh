#!/bin/bash

# Define an array of image names
images=(
  "cgr.dev/chainguard-private/nginx:latest"
  "cgr.dev/chainguard-private/nginx:1.26"
  "cgr.dev/chainguard-private/nginx:1.24"
  "cgr.dev/chainguard-private/nginx:1.26.1"
  "cgr.dev/chainguard-private/python:3.9"
  "cgr.dev/chainguard-private/python:3.10"
  "cgr.dev/chainguard-private/python:3.11"
  "cgr.dev/chainguard-private/python:3.12"
  "cgr.dev/chainguard-private/python:3.11.9"
)


# Loop through each item and append ":latest" if no tag is present
for i in "${!images[@]}"; do
    if [[ "${images[i]}" != *:* ]]; then
        images[i]="${images[i]}:latest"
    fi
    echo "Pulling ${images[i]}"
    if docker pull ${images[i]} 2>&1 | grep -iq "error"; then
      echo "Error encountered while pulling $image. Exiting..."
      exit 1
    fi
    images[i]=$(docker inspect "${images[i]}" | jq -r '.[0].RepoDigests[0]')
    # images[i]=$(docker inspect --format='{{json .RepoDigests}}' "${images[i]}" | jq -r '.[0]')
    echo "${images[i]}"
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

for IMAGE in "${images[@]}"; do
  
  # echo "$IMAGE"
  # Capture the JSON output in a variable
  output=$(grype $IMAGE -o json 2>/dev/null | jq -c '{Total: [.matches[].vulnerability] | length, Critical: [.matches[] | select(.vulnerability.severity == "Critical")] | length, High: [.matches[] | select(.vulnerability.severity == "High")] | length, Medium: [.matches[] | select(.vulnerability.severity == "Medium")] | length, Low: [.matches[] | select(.vulnerability.severity == "Low")] | length, WontFix: [.matches[] | select(.vulnerability.fix.state == "wont-fix")] | length }')
  
  echo "$output"
  critical=$(jq '.Critical' <<< "$output")
  high=$(jq '.High' <<< "$output")
  medium=$(jq '.Medium' <<< "$output")
  low=$(jq '.Low' <<< "$output")
  wontfix=$(jq '.WontFix' <<< "$output")
  total=$(jq '.Total' <<< "$output")

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
