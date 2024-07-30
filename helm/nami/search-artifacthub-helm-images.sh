#!/bin/bash

HELM_CSV_FILE=$(mktemp -q XXXXXX.csv)

printf '\n'
printf '=================================================================\n'
printf '=== Searching artifacthub.io for images listed in helm charts ===\n'
printf '=================================================================\n'
printf '\n'

repositories=()
urls=()

offset=0
output=""
kindresults=()

# Function to call Artifact Hub API
call_api() {
  local offset=$1
  URL="https://artifacthub.io/api/v1/packages/search?facets=false&limit=20&kind=0&deprecated=false&sort=stars&offset=$offset"
  curl --max-time 10 -s -X 'GET' -H 'accept: application/json' "$URL" | jq -r '.packages[] | select(.stars >= 100)'
}

# Initial call to Artifact Hub API
output=$(call_api $offset)
kindresults+=("$output")
offset=$((offset + 20))

while [[ -n "$output" && "$output" != "[]" ]]; do
  
  output=$(call_api $offset)
  kindresults+=("$output")
    
  # Check if output is empty or just contains an empty array
  if [[ -z "$output" || "$output" == "[]" ]]; then
    break
  fi

  offset=$((offset + 20))

done
# Join all JSON results into a single JSON array
joined_results=$(printf '%s\n' "${kindresults[@]}" | jq -s '.')

if [[ -n "$joined_results" ]]; then
#   echo "$joined_results" > "$HELM_CSV_FILE"

  repositories=($(echo "$joined_results" | jq -r '.[] | select(.repository.name != null and .repository.url != null) | .repository.name'))
  urls=($(echo "$joined_results" | jq -r '.[] | select(.repository.name != null and .repository.url != null) | .repository.url'))
  numrepos=${#repositories[@]}
  printf 'Total %s helm charts found: %s\n' "$numrepos" "$numrepos"
  for ((i=0; i<numrepos; i++)); do
    
    helm repo add "${repositories[i]}" "${urls[i]}" &> /dev/null
    helm repo update "${repositories[i]}" &> /dev/null
    
    chart_names=()
    while IFS= read -r line; do
        chart_names+=("$line")
    done < <(helm search repo "${repositories[i]}" | awk 'NR > 1 {print $1}' | sed "s/${repositories[i]}\///")

    for chart in "${chart_names[@]}"; do
        echo "chart=$chart"
        echo "url=${urls[i]}"
        output=$(nami helm images --repo="${urls[i]}" --chart="$chart" 2>/dev/null)
        # sanitized_output=$(echo "$output" | sed 's/"/""/g')
        # echo "${urls[i]},${chart},${sanitized_output}" >> "$HELM_CSV_FILE"
        # Parse the output to get the YAML file and image reference
        echo "$output" | while IFS= read -r line; do
        if [[ $line == •* ]]; then
            yaml_file=$(echo "$line" | sed 's/• //' | sed 's/[ \t]*$//')
        elif [[ $line == └──* ]]; then
            image_reference=$(echo "$line" | sed 's/└── • //' | sed 's/[ \t]*$//')
            if [[ -n "$image_reference" ]]; then
                echo "\"${urls[i]}\",\"${chart}\",\"${yaml_file}\",\"${image_reference}\"" >> "$HELM_CSV_FILE"
            fi
        fi
        done  
    done
  done


else
  printf 'Total %s helm charts found: 0\n'
fi

printf '\nResults saved to %s\n' "$HELM_CSV_FILE"
exit
