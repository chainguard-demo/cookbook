#!/usr/bin/env bash
set -euo pipefail

show_diff=false
diff_file=""
fetch_mode=false
fetch_pkg=""
fetch_version=""
fetch_suffix=""

usage() {
    cat >&2 <<EOF
Usage:
  $0 [options] <sdist1.tar.gz> <sdist2.tar.gz>
  $0 [options] --fetch <package> <version> <suffix>

Options:
  -d, --diff              show full line-level diffs (unified)
  -o, --output <file>     write unified diff to <file> (implies -d)
  --fetch <pkg> <version> <suffix>
                          download the base and remediated sdists from
                          libraries.cgr.dev, then compare them.
                          Requires CG_PYTHON_USER and CG_PYTHON_PASS.
                          Example: --fetch onnx 1.18.0 cgr.1
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--diff)
            show_diff=true
            shift
            ;;
        -o|--output)
            diff_file="$2"
            shift 2
            ;;
        --fetch)
            fetch_mode=true
            fetch_pkg="${2:-}"
            fetch_version="${3:-}"
            fetch_suffix="${4:-}"
            if [[ -z "$fetch_pkg" || -z "$fetch_version" || -z "$fetch_suffix" ]]; then
                echo "Error: --fetch requires <package> <version> <suffix>" >&2
                usage
                exit 1
            fi
            shift 4
            ;;
        --)
            shift
            break
            ;;
        -*)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

if $fetch_mode; then
    : "${CG_PYTHON_USER:?CG_PYTHON_USER is not set. Export it before running --fetch.}"
    : "${CG_PYTHON_PASS:?CG_PYTHON_PASS is not set. Export it before running --fetch.}"

    base_name="${fetch_pkg}-${fetch_version}.tar.gz"
    remediated_name="${fetch_pkg}-${fetch_version}+${fetch_suffix}.tar.gz"
    base_url="https://libraries.cgr.dev/python/simple/${fetch_pkg}/${fetch_version}/${base_name}"
    remediated_url="https://libraries.cgr.dev/python-remediated/simple/${fetch_pkg}/${fetch_version}+${fetch_suffix}/${remediated_name}"

    for pair in "$base_name|$base_url" "$remediated_name|$remediated_url"; do
        name="${pair%%|*}"
        url="${pair##*|}"
        if [[ -f "$name" ]]; then
            echo "Already have $name — skipping download" >&2
        else
            echo "Downloading $url" >&2
            curl -fLO -u "${CG_PYTHON_USER}:${CG_PYTHON_PASS}" "$url"
        fi
    done

    set -- "$base_name" "$remediated_name"
fi

if [[ $# -ne 2 ]]; then
    usage
    exit 1
fi

sdist_a="$1"
sdist_b="$2"

if [[ -n "$diff_file" ]]; then
    show_diff=true
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

extract_root() {
    local archive="$1" dest="$2"
    mkdir -p "$dest"
    tar -xzf "$archive" -C "$dest"
    local inner
    inner=$(find "$dest" -mindepth 1 -maxdepth 1 -type d | head -n1)
    echo "$inner"
}

a_root=$(extract_root "$sdist_a" "$tmp/a")
b_root=$(extract_root "$sdist_b" "$tmp/b")

echo "A: $sdist_a -> $a_root" >&2
echo "B: $sdist_b -> $b_root" >&2
echo >&2

# diff exits 1 when differences are found — that's success for us.
run_diff() {
    if $show_diff; then
        diff -ruN \
            --exclude='PKG-INFO' \
            --exclude='*.egg-info' \
            "$a_root" "$b_root" \
            | sed -e "s|$a_root|a|g" -e "s|$b_root|b|g" || [[ $? -eq 1 ]]
    else
        diff -rq \
            --exclude='PKG-INFO' \
            --exclude='*.egg-info' \
            "$a_root" "$b_root" \
            | sed -e "s|$a_root|A|g" -e "s|$b_root|B|g" || [[ $? -eq 1 ]]
    fi
}

if [[ -n "$diff_file" ]]; then
    run_diff > "$diff_file"
    echo "Diff written to: $diff_file" >&2
else
    run_diff
fi
