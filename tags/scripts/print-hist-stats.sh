#!/bin/bash

show_help() {
    echo ""
    echo "Usage: $0 image-stream-base-uri image-stream-version"
    echo "       $0 cgr.dev/chainguard-private/python 3.9"
    echo "  -h, --help          Display this help message and exit"
    echo ""
}

if [ $# -ne 2 ]; then
    show_help
    exit 1
fi

# Formatting variables
RESET="\033[0m"
EMT="\033[38;5;118m" # Toxic green

repository="$1"
version="$2"

# Removing cgr.dev/
repository=${1#cgr.dev/}

# Fetch history using the provided parameters
history=$(curl -s -H "$(crane auth token -H cgr.dev/$repository)" "https://cgr.dev/v2/$repository/_chainguard/history/$version" | jq .)
IFS=$'\n' read -r -d '' -a historyapidigestarray <<< $(echo $history | jq -r '.history[].digest')

oldest_timestamp=$(echo "$history" | jq -r '.history[0].updateTimestamp' | cut -d'T' -f1)
newest_timestamp=$(echo "$history" | jq -r '.history[-1].updateTimestamp' | cut -d'T' -f1)
days_difference=$(( ( $(date -d "$newest_timestamp" +%s) - $(date -d "$oldest_timestamp" +%s) ) / 86400 ))
if [ ${#historyapidigestarray[@]} -gt 1 ]; then
    average_days_per_build=$(echo "scale=1; $days_difference / (${#historyapidigestarray[@]} - 1)" | bc)
else
    average_days_per_build=0
fi

echo ""
echo -e "Number of unique rebuilds: ${EMT}${#historyapidigestarray[@]}${RESET}"
echo -e "Days active: ${EMT}$days_difference${RESET}"
echo -e "Oldest build: ${EMT}$oldest_timestamp${RESET}"
echo -e "Newest build: ${EMT}$newest_timestamp${RESET}"
echo -e "Average days between rebuilds: ${EMT}$average_days_per_build${RESET}"
echo ""