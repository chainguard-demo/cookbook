# Tags Directory

<br/>

>
> #### A note
>
> - longer examples are moved to the scripts directory
> - Make sure to replace "cgr.dev/chainguard-private" with your enterprise repository url (i.e. cgr.dev/yourdomain.com)
>
>

<br/>

### Check main package version installed

```bash
docker run --rm -it --user=0 --entrypoint sh \
  cgr.dev/chainguard-private/cosign:2.2.4-r8-dev -c ' \
    apk update --quiet && 
    apk list --installed | grep "^cosign" | awk "{print \$1}" 2>/dev/null'
```

### Print multi-arch image digests

```bash
IMAGE="cgr.dev/chainguard-private/prometheus:2.53.1-r1-dev-202408031818"
EMT="\033[38;5;118m"; W="\033[0;37m" # Emerald and white output color

# Retrieve digests
multiarchdigest=$(crane digest $IMAGE)
arm64digest=$(crane manifest $IMAGE | jq -r '.manifests[] | select(.platform.architecture=="arm64") | .digest')
amd64digest=$(crane manifest $IMAGE | jq -r '.manifests[] | select(.platform.architecture=="amd64") | .digest')

# Print digests with colors
echo
echo -e "Multi-arch digest: ${EMT}$IMAGE@$multiarchdigest${W}"
echo -e "ARM64 digest: ${EMT}$IMAGE@$arm64digest${W}"
echo -e "AMD64 digest: ${EMT}$IMAGE@$amd64digest${W}\n"

crane ls cgr.dev/chainguard-private/python | grep -E '^v?3\.11\.[0-9]+$' | sort -V | tail -n 1
crane ls cgr.dev/chainguard-private/python | grep -E '^v?3\.11\.9-r.*[^-dev]$' | sort -V | tail -n 1
```

### Get the last 3 python 3.11 patch releases

```bash
crane ls --omit-digest-tags cgr.dev/chainguard-private/python | grep -E '^v?3\.11\.[0-9]+$' | sort -Vr | head -n 3
```

### Get the last 3 python 3.11.9 revisions

```bash
crane ls cgr.dev/chainguard-private/python | grep -E '^v?3\.11\.9-r.*[^-dev]$' | sort -Vr | head -n 3
```

### Get the last 3 unique tags

```bash
crane ls cgr.dev/chainguard-private/prometheus | grep -E '^[^ ]+-[0-9]{12}$' | grep -v '^latest' | sort -Vr | head -n 3
```

### Get last 3 prometheus 2.52 unique tags (exclude -dev tags)

```bash
crane ls cgr.dev/chainguard-private/prometheus | grep -E '^2\.52[^ ]+-[0-9]{12}$' | grep -v '^latest' | grep -v '\-dev' | sort -Vr | head -n 3
```

### Diff API - check if an ugprade fixes any Critical or High CVEs
```bash
chainctl images diff \
    cgr.dev/chainguard-private/python:3.11.8 \
    cgr.dev/chainguard-private/python:3.11.9 2>/dev/null | \
    jq '.vulnerabilities.removed[] | select(.severity == "Critical" or .severity == "High") .id'
```