# RPM to APK Mapper

A Python tool that maps Red Hat UBI 9 RPM packages to equivalent Chainguard APK packages.

## Overview

This tool:
1. Queries all available RPMs from Red Hat UBI 9 repositories
2. Filters to the latest version of each package (preferring x86_64 architecture)
3. Searches for equivalent packages in Chainguard's Wolfi repository
4. Generates a CSV file mapping RPMs to APKs

## Requirements

- Python 3.6+
- Docker or Podman
- Internet connection (to pull container images)

## Installation

No additional Python packages required - uses only standard library.

Make the script executable:

```bash
chmod +x rpm_to_apk_mapper.py
```

## Usage

### Basic Usage

```bash
python3 rpm_to_apk_mapper.py
```

This will:
- Pull the Red Hat UBI 9 image
- Pull the Chainguard Wolfi base image
- Generate `rpm_to_apk_mapping.csv` in the current directory

### Options

```bash
python3 rpm_to_apk_mapper.py --help
```

Available options:

- `--output FILE`, `-o FILE`: Specify output CSV file (default: `rpm_to_apk_mapping.csv`)
- `--runtime {docker,podman}`: Specify container runtime (default: `docker`)

### Examples

Use Podman instead of Docker:
```bash
python3 rpm_to_apk_mapper.py --runtime podman
```

Specify custom output file:
```bash
python3 rpm_to_apk_mapper.py --output my_mappings.csv
```

## Output Format

The generated CSV contains two columns:

| Column | Description |
|--------|-------------|
| `rpm_name` | Name of the RPM package |
| `apk_name` | Name of matching Chainguard APK (empty if no match found) |

## Matching Logic

The tool attempts to match RPMs to APKs using the following strategies:

1. **Exact name match**: Direct match on package name (e.g., `bash` → `bash`)
2. **Common transformations**:
   - **-devel to -dev**: RPMs ending in `-devel` match to APKs ending in `-dev` (e.g., `python-devel` → `python-dev`)
   - **-libs removal**: RPMs ending in `-libs` match to APKs without the suffix (e.g., `curl-libs` → `curl`)
   - **-tools removal**: RPMs ending in `-tools` match to APKs without the suffix (e.g., `git-tools` → `git`)
   - **lib prefix removal**: RPMs starting with `lib` match to APKs without the prefix (e.g., `libxml2` → `xml2`)

## Example Output

```csv
rpm_name,apk_name
bash,bash
glibc,glibc
python-devel,python-dev
systemd-libs,
curl-libs,curl
```

## Limitations

- Matching is name-based and heuristic; version compatibility is not verified
- Not all RPM packages have APK equivalents
- Some packages may have different names or be bundled differently in Chainguard
- The tool uses Chainguard's Wolfi repository, which is the base for Chainguard images
- Only queries packages available in the default UBI 9 repositories (requires active Red Hat subscription for full package access)
- Version comparison is heuristic-based; edge cases with complex version schemes may not sort perfectly

## Troubleshooting

### Docker/Podman not found

Ensure Docker or Podman is installed and accessible:
```bash
docker --version
# or
podman --version
```

### Permission denied

If you get permission errors with Docker, you may need to:
- Run with sudo
- Add your user to the docker group
- Use `--runtime podman` instead

### Image pull failures

If images fail to pull:
- Check your internet connection
- Ensure you can access registry.access.redhat.com and cgr.dev
- Try pulling manually first:
  ```bash
  docker pull registry.access.redhat.com/ubi9/ubi:latest
  docker pull cgr.dev/chainguard/wolfi-base:latest
  ```

## How It Works

1. **RPM Discovery**: Runs `yum list available` in a UBI 9 container to list all available packages from repositories
2. **Version Filtering**: Groups packages by name and selects only the latest version
   - Implements RPM-style version comparison (handles complex version strings)
   - Prefers x86_64 architecture when multiple architectures have the same version
   - Falls back to noarch if x86_64 is not available
3. **APK Discovery**: Runs `apk search -a --no-cache -q | sort | uniq` in a Chainguard Wolfi container to get all available packages
4. **Matching**: Applies name-based matching with common transformations
5. **CSV Generation**: Writes results to a CSV file with RPM to APK mappings

Note: The initial run may take 1-2 minutes as it queries thousands of packages from the UBI repositories.
