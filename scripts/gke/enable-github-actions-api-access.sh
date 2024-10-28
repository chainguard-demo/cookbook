#!/bin/bash

# Define variables for region, project, and cluster
REGION="us-central1"
PROJECT="josborne-gke-demo"
CLUSTER_NAME="autopilot-cluster-1"

GITHUB_ACTIONS_CIDR_LIST=($(curl -s https://api.github.com/meta | jq -r '.actions[] | select(test("^[0-9.]+/[0-9]+$"))' | paste -sd " "))

aggregated_cidrs=()
count=0

// the gcloud command will only accept 100 CIDRs at a time so doing exactly that
for cidr in "${GITHUB_ACTIONS_CIDR_LIST[@]}"; do
    
    aggregated_cidrs+=("$cidr")
    count=$((count + 1))

    # If we have reached 100 CIDRs, run gcloud
    if (( count == 100 )); then
        cidrscommasinteadofspaces="$(IFS=,; echo "${aggregated_cidrs[*]}")"
        echo "Adding subnets: $cidrscommasinteadofspaces"
        gcloud container clusters update "$CLUSTER_NAME" \
            --region "$REGION" \
            --project "$PROJECT" \
            --enable-master-authorized-networks \
            --master-authorized-networks="$cidrscommasinteadofspaces"
        count=0
        aggregated_cidrs=()
    fi
done

// Adding the rest of the cidrs
if (( count > 0 )); then
    cidrscommasinteadofspaces="$(IFS=,; echo "${aggregated_cidrs[*]}")"
    echo "Adding subnets: $cidrscommasinteadofspaces"
    gcloud container clusters update "$CLUSTER_NAME" \
            --region "$REGION" \
            --project "$PROJECT" \
            --enable-master-authorized-networks \
            --master-authorized-networks="$cidrscommasinteadofspaces"
fi
