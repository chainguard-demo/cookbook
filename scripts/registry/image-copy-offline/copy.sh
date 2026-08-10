#!/usr/bin/env bash

set -eo pipefail


readonly NAME=$(basename "$0")
readonly LOCKFILE=/tmp/$NAME
readonly LOCKFD=200


#Remove lock file if signal 1, 2, 3, or 6.
trap prem_end 1 2 3 6

prem_end ()
{
  echo "Premature end detected, removing lock"
  rm -rf "$LOCKFILE".lock
  echo "Finished"
  exit 1
}

#Lock functions
lock () {
        local fd=${2:-$LOCKFD}
        local lockfile=$LOCKFILE.lock

        # create the lock file
        eval "exec $fd>$lockfile"

        #get the lock
        flock -n "$fd" && return 0 || return 1
}

# Remove lock
unlock () {
        local fd=${2:-$LOCKFD}
        local lockfile=$LOCKFILE.lock

        flock -u "$fd"
        rm -f "$lockfile"
}

# Print formatted errors and exit
errexit () {
        local err="$@"

        errtext "$err"
        exit 1
}

# Print formatted errors
errtext () {
        local err="$@"
        local RED='\033[0;31m'
        local RESET='\033[0m'

        printf '%bERROR: %s%b\n' "$RED" "$*" "$RESET" >&2
}

# Print formatted log info
loginfo () {
        local info="$@"
        local GREEN='\033[0;32m'
        local RESET='\033[0m'

        printf '%b\n' "${GREEN}INFO: ${info}${RESET}"

}

#Help function
function script_help () {
        echo "
        Usage: $NAME [options]

        -f file containing image data

        -h   this help text

        Example:
                $(basename "$0") pull -f images.txt | pull images locally and store them
                $(basename "$0") push -f images.txt | push images to the registry defined
                $(basename "$0") full -f images.txt | pull images locally and push in one command

        Image data is delimited by an = sign. The first key is the upstream image,
        the second key is the local file name, and the third key is the local registry image.

        For example:
        cgr.dev/foo.com/go:latest=localhost:5000/go:newtag

        "

        exit "${1:-0}"
}


function push() {
	while IFS='=' read -r upstream local_registry; do
                local_file=$(awk -F/ '{print $3}' <<< "$upstream" | sed -E 's/:|@/_/g')
                loginfo "pushing $local_file to $local_registry"

                if ! output=$(crane push "$local_file" "$local_registry" 2>&1); then
                        errtext "$output"
                fi

                upstream_digest=$(crane digest "$upstream")
                local_digest=$(crane digest "$local_registry")

                [[ "$upstream_digest" != "$local_digest" ]] && errtext "mismatch between $upstream_digest and $local_digest"

	done < "$FILE"
}

function pull() {
	while IFS='=' read -r upstream local_registry; do
                local_file=$(awk -F/ '{print $3}' <<< "$upstream" | sed -E 's/:|@/_/g')

                if [[ -d "$local_file" ]]; then
                        loginfo "skipping $local_file because it already exists"
                        continue
                fi

                loginfo "pulling $upstream and storing in $local_file"

                if ! output=$(crane pull --format=oci "$upstream" "$local_file" 2>&1); then
                        errtext "$output"
                fi
	done < "$FILE"
}

function pull_push() {
        pull || errtext
        push
}

#Show help if no arguments or options are passed
[[ ! "$*" ]] && script_help 1
OPTIND=1

subcmd=""

# grab subcommand if it's first'
if [[ $# -gt 0 && $1 != -* ]]; then
        subcmd=$1
        shift
fi

#Read command line options
#A colon after a flag means it takes an argument
#Example with extra argument called "a"
#while getopts "a:h" opt; do
#    case "$opt" in
#      a) variable=$OPTARG ;;
#      h) script_help ;;
#      \?) script_help 1 ;;
#    esac
#done
while getopts "hf:" opt; do
        case "$opt" in
                f) FILE=$OPTARG ;;
                h) script_help ;;
                \?) script_help 1 ;;
        esac
done
shift $(($OPTIND-1));

# grab subcommand after flags
if [[ -z $subcmd && $# -gt 0 ]]; then
        subcmd=$1
        shift
fi

#Main function
main () {
        if [[ -z "$FILE" ]]; then
                errexit "file flag must be defined"
        fi

        if command -v flock >/dev/null 2>&1
        then
                lock "$NAME" || errexit "An instance of $NAME is still running."
        fi

        if [[ -n "$subcmd" ]]; then
                case "$subcmd" in
                        pull) pull; return ;;
                        push) push; return ;;
                        full) pull_push; return ;;
                        *) errexit "name and tag flags requires advisories or vulnerabilities" ;;
                esac
        fi

        if command -v flock >/dev/null 2>&1
        then
                unlock
        fi
}

main  "$subcmd"

