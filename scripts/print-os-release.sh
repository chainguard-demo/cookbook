#!/bin/bash

declare -A os_counts

images=(
  ""
)

# Function to parse os-release content
parse_os_release() {
  local content="$1"
  if echo "$content" | grep -q '^ID='; then
    echo "$content" | grep '^ID=' | head -n1 | cut -d= -f2 | tr -d '"'
  elif echo "$content" | grep -q '^NAME='; then
    echo "$content" | grep '^NAME=' | head -n1 | cut -d= -f2 | tr -d '"'
  else
    echo "$content" | head -n 1
  fi
}


# Function to detect OS from tarball
detect_os_tarball() {
  local tarfile="$1"

  # Try os-release files
  for p in usr/lib/os-release etc/os-release lib/os-release; do
    if os_content=$(tar -xOf "$tarfile" "$p" 2>/dev/null); then
      parse_os_release "$os_content"
      return 0
    fi
  done

  # Try alternative files
  tar -xOf "$tarfile" etc/debian_version 2>/dev/null >/dev/null && echo "debian" && return 0
  tar -xOf "$tarfile" etc/alpine-release 2>/dev/null >/dev/null && echo "alpine" && return 0
  tar -xOf "$tarfile" etc/redhat-release 2>/dev/null >/dev/null && echo "rhel" && return 0
  tar -xOf "$tarfile" etc/system-release 2>/dev/null >/dev/null && echo "rhel" && return 0
  tar -tf "$tarfile" | grep -q "bin/busybox" && echo "alpine" && return 0

  # Check if it's a scratch image (minimal file count, excluding docker runtime files)
  local file_count=$(tar -tf "$tarfile" | grep -Ev '^(\.|dev/|proc/|sys/|etc/(hostname|hosts|resolv\.conf|mtab))' | wc -l)
  if [ "$file_count" -le 3 ]; then
    echo "scratch"
    return 0
  fi

  return 1
}

for i in "${!images[@]}"; do

  if [[ "${images[i]}" != *:* ]]; then
      images[i]="${images[i]}:latest"
  fi

  origimagestr="${images[i]}"

  os_name=""
  tmpfile=$(mktemp)

  # Try crane export from registry first
  if crane export --platform=linux/amd64 "${images[i]}" "$tmpfile" 2>/dev/null; then
    os_name=$(detect_os_tarball "$tmpfile")
  else
    # Crane failed (likely rate limit), try using docker save for local images
    docker_tarball=$(mktemp)
    if docker save "${images[i]}" > "$docker_tarball" 2>/dev/null; then
      # Extract OCI layout from docker save
      oci_dir=$(mktemp -d)
      tar -xf "$docker_tarball" -C "$oci_dir" 2>/dev/null

      # Create merged filesystem directory
      fs_dir=$(mktemp -d)

      # Parse manifest.json to get layer paths
      if [ -f "$oci_dir/manifest.json" ]; then
        # Extract each layer blob in order
        jq -r '.[0].Layers[]' "$oci_dir/manifest.json" 2>/dev/null | while read -r layer_path; do
          layer_file="$oci_dir/$layer_path"
          if [ -f "$layer_file" ]; then
            tar -xf "$layer_file" -C "$fs_dir" 2>/dev/null || true
          fi
        done
      fi

      # Create filesystem tarball
      (cd "$fs_dir" && tar -cf "$tmpfile" . 2>/dev/null)

      os_name=$(detect_os_tarball "$tmpfile")

      sudo rm -rf "$oci_dir" "$fs_dir" "$docker_tarball"
    else
      os_name="PULL_ERROR"
    fi
  fi
  rm -f "$tmpfile"

  # If still unknown, check OCI annotations for base image info
  if [ -z "$os_name" ] && [ "$os_name" != "PULL_ERROR" ]; then
    # Try registry first, fall back to local docker daemon
    base_name=$(crane config --platform=linux/amd64 "${images[i]}" 2>/dev/null | jq -r '.config.Labels."org.opencontainers.image.base.name" // empty' 2>/dev/null)
    if [ -z "$base_name" ]; then
      base_name=$(crane config --platform=linux/amd64 "docker-daemon:${images[i]}" 2>/dev/null | jq -r '.config.Labels."org.opencontainers.image.base.name" // empty' 2>/dev/null)
    fi
    if [ -n "$base_name" ]; then
      # Extract OS from base image name
      case "$base_name" in
        *debian*) os_name="debian" ;;
        *ubuntu*) os_name="ubuntu" ;;
        *alpine*) os_name="alpine" ;;
        *rhel*|*redhat*) os_name="rhel" ;;
        *centos*) os_name="centos" ;;
        *fedora*) os_name="fedora" ;;
        *photon*) os_name="photon" ;;
        *distroless*)
          # Distroless images are Debian-based
          os_name="debian"
          ;;
        *scratch*) os_name="scratch" ;;
      esac
    fi
  fi
  if [ -z "$os_name" ]; then
    os_name="UNKNOWN"
  fi
  echo "$origimagestr $os_name"

  # Track OS counts
  os_counts[$os_name]=$((${os_counts[$os_name]:-0} + 1))
done

echo "---------------------------------------------"
echo "OS Distribution Summary:"
echo "---------------------------------------------"

# Print sorted counts
for os in $(printf '%s\n' "${!os_counts[@]}" | sort); do
  printf "%-15s : %d\n" "$os" "${os_counts[$os]}"
done
