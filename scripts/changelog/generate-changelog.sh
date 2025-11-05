#!/bin/bash

print_dots() {
    while true; do
        echo -n "."
        sleep 1
    done
}

show_help() {
    echo ""
    echo "Usage: $0 [options] <image_name> <previous_version> <new_version>"
    echo ""
    echo "Options:"
    echo "  --platform          Specifies the platform in the form os/arch[/variant][:osversion] (default: linux/amd64)"
    echo "  --image-ref-type    tags | digests (default: tags)"
    echo "  -h, --help          Display this help message and exit"
    echo ""
}

# Formatting variables
header="\e[1m"  # Bold text
normal="\e[0m"  # Normal text
green="\e[32m"  # Green
red="\e[31m"    # Red
yellow="\e[33m"    # Yellow
blue="\e[34m"   # Blue
purple="\e[35m"   # Purple
cyan="\e[36m"
lightgrey="\e[37m"

# Defaults
platform="linux/amd64"
reftype="tags"

# Check if they specified the platform
if [[ "$1" == "--platform" ]]; then
    platform="$2"
    shift 2
fi

# Prepend '@' to versions if digests is true
if [ "$1" = "--image-ref-type=digests" ] || [ "$1" = "--image-ref-type" -a "$2" = "digests" ]; then
    reftype="digests"
    shift
    if [[ "$1" == "digests" ]]; then
        shift
    fi
fi

# Assigning arguments to variables
image_name="$1"
previous_version="$2"
new_version="$3"

if [ "$reftype" = "digests" ]; then
    new_version="@$new_version"
    previous_version="@$previous_version"
fi

echo ""
echo -ne "Platform: ${purple}$platform${normal}\n"
echo -ne "Image Reference Type: ${purple}$reftype${normal}\n"
echo -ne "Image Name: ${purple}$image_name${normal}\n"
echo -ne "Previous Version: ${purple}$previous_version${normal}\n"
echo -ne "New Version: ${purple}$new_version${normal}\n"
echo ""

# Check if all required arguments are provided
if [[ -z "$image_name" || -z "$previous_version" || -z "$new_version" ]]; then
    show_help
    exit 1
fi

echo -ne "${header}Generating CHANGELOG${normal}"
print_dots &
dots_pid=$!
diff_api_json_output=$(chainctl images diff --platform="$platform" "$image_name":"$previous_version" "$image_name":"$new_version" 2>/dev/null)
kill $dots_pid > /dev/null 2>&1
echo ""
echo ""

echo -ne "Packages Added:${normal}"
packages_added=$(echo "$diff_api_json_output" | jq -r '.packages.added[]? | select(.reference | startswith("pkg:apk")) | .name')
if [ -z "$packages_added" ]; then
    echo -n ""
else
    for pkg_added in $packages_added; do
        echo -ne "\n  - ${green}$pkg_added${normal}"
    done
        
fi

echo -ne "\nPackages Removed:${normal}"
packages_removed=$(echo "$diff_api_json_output" | jq -r '.packages.removed[]? | select(.reference | startswith("pkg:apk")) | .name')
if [ -z "$packages_removed" ]; then
    echo -n ""
else
    for pkg_rm in $packages_removed; do
        echo -ne "\n  - ${red}$pkg_rm${normal}"
    done    
fi

echo -ne "\nPackages Changed:${normal}"
packages_changed=$(echo "$diff_api_json_output" | jq -r '.packages.changed[]? | "\(.name) \(.previous.version) \(.current.version)"')
if [ -z "$packages_changed" ]; then
    echo -n ""
else
    echo "$packages_changed" | while read -r name prev_version curr_version; do
        if [[ $name == *".yaml" ]]; then
            echo -ne "\n  - ${red}$name cannot be diffed: \n    - Old version: $prev_version \n    - New version: $curr_version${normal}"
        else
            prev_version=${prev_version//_/.}
            curr_version=${curr_version//_/.}
            IFS='.' read -ra PREV <<< "$prev_version"
            IFS='.' read -ra CURR <<< "$curr_version"
            upgraded=false
            downgraded=false
            for i in {0..2}; do
                if [[ ${CURR[i]} -gt ${PREV[i]} ]]; then
                    upgraded=true
                    break
                elif [[ ${CURR[i]} -lt ${PREV[i]} ]]; then
                    downgraded=true
                    break
                fi
            done
        fi
        if $upgraded; then
            echo -ne "\n  - ${blue}$name: Upgraded from $prev_version to $curr_version${normal}"
        elif $downgraded; then
            echo -ne "\n  - ${red}$name: Downgraded from $prev_version to $curr_version${normal}"
        fi
    done
fi

# Extracting and printing vulnerabilities removed
echo -e "\nVulnerabilities Removed:${normal}"

# Define an array of severities for organization
declare -a severities=("Critical" "High" "Medium" "Low" "Unknown")

# Loop through each severity and print vulnerabilities
for severity in "${severities[@]}"; do
    # Extract vulnerabilities of this severity
    vulnerabilities=$(echo "$diff_api_json_output" | jq -r --arg sev "$severity" '.vulnerabilities.removed[]? | select(.severity == $sev) | .id')

    # Check if there are vulnerabilities of this severity
    if [ -z "$vulnerabilities" ]; then
        echo -e "  ${purple}${severity}:${normal}"
    else
        echo -e "  ${purple}${severity}:${normal}"
        for vuln in $vulnerabilities; do
            echo -ne "    - $vuln${normal}\n"
        done
    fi
done
echo -e "\n${header}Finished!\n${normal}"
