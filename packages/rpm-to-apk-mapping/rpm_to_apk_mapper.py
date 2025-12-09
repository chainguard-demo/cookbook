#!/usr/bin/env python3
"""
RPM to APK Mapper
Maps Red Hat UBI 9 RPMs to equivalent Chainguard APKs
"""

import subprocess
import csv
import sys
import re
from typing import List, Dict, Optional, Tuple
from collections import defaultdict
import argparse


class ContainerRunner:
    """Handle container operations"""

    def __init__(self, runtime: str = "docker"):
        self.runtime = runtime
        self._check_runtime()

    def _check_runtime(self):
        """Check if container runtime is available"""
        try:
            subprocess.run(
                [self.runtime, "--version"],
                capture_output=True,
                check=True
            )
        except (subprocess.CalledProcessError, FileNotFoundError):
            print(f"Error: {self.runtime} is not available", file=sys.stderr)
            sys.exit(1)

    def run_command(self, image: str, command: List[str]) -> str:
        """Run a command in a container and return output"""
        try:
            result = subprocess.run(
                [self.runtime, "run", "--rm", image] + command,
                capture_output=True,
                text=True,
                check=True
            )
            return result.stdout
        except subprocess.CalledProcessError as e:
            print(f"Error running container command: {e}", file=sys.stderr)
            print(f"stderr: {e.stderr}", file=sys.stderr)
            sys.exit(1)


class RPMExtractor:
    """Extract RPM package information from UBI 9"""

    def __init__(self, container_runner: ContainerRunner):
        self.container_runner = container_runner
        self.ubi_image = "registry.access.redhat.com/ubi9/ubi:latest"

    @staticmethod
    def _parse_version(version_release: str) -> Tuple[List, List]:
        """Parse version-release into comparable components"""
        if '-' in version_release:
            version, release = version_release.rsplit('-', 1)
        else:
            version, release = version_release, '0'

        def split_version_parts(v: str) -> List:
            """Split version into numeric and string parts for comparison"""
            parts = []
            for part in re.split(r'[.\-_]', v):
                if part.isdigit():
                    parts.append(('num', int(part)))
                else:
                    # Split alpha and numeric within part
                    for subpart in re.findall(r'\d+|\D+', part):
                        if subpart.isdigit():
                            parts.append(('num', int(subpart)))
                        else:
                            parts.append(('str', subpart))
            return parts

        return split_version_parts(version), split_version_parts(release)

    @staticmethod
    def _compare_versions(v1: str, v2: str) -> int:
        """
        Compare two version-release strings
        Returns: 1 if v1 > v2, -1 if v1 < v2, 0 if equal
        """
        ver1_parts, rel1_parts = RPMExtractor._parse_version(v1)
        ver2_parts, rel2_parts = RPMExtractor._parse_version(v2)

        # Compare versions first
        for i in range(max(len(ver1_parts), len(ver2_parts))):
            p1 = ver1_parts[i] if i < len(ver1_parts) else ('num', 0)
            p2 = ver2_parts[i] if i < len(ver2_parts) else ('num', 0)

            # Numbers always compare as greater than strings
            if p1[0] == 'num' and p2[0] == 'str':
                return 1
            if p1[0] == 'str' and p2[0] == 'num':
                return -1

            # Compare same types
            if p1[1] > p2[1]:
                return 1
            if p1[1] < p2[1]:
                return -1

        # Versions equal, compare releases
        for i in range(max(len(rel1_parts), len(rel2_parts))):
            p1 = rel1_parts[i] if i < len(rel1_parts) else ('num', 0)
            p2 = rel2_parts[i] if i < len(rel2_parts) else ('num', 0)

            if p1[0] == 'num' and p2[0] == 'str':
                return 1
            if p1[0] == 'str' and p2[0] == 'num':
                return -1

            if p1[1] > p2[1]:
                return 1
            if p1[1] < p2[1]:
                return -1

        return 0

    def _filter_latest_rpms(self, all_rpms: List[Dict[str, str]]) -> List[Dict[str, str]]:
        """
        Filter to keep only the latest version of each package
        Prefer x86_64 architecture when versions are equal
        """
        # Group by package name
        packages = defaultdict(list)
        for rpm in all_rpms:
            packages[rpm['name']].append(rpm)

        latest_rpms = []
        for pkg_name, versions in packages.items():
            if not versions:
                continue

            # Find the latest version
            latest = versions[0]
            for rpm in versions[1:]:
                comparison = self._compare_versions(
                    f"{rpm['version']}-{rpm['release']}",
                    f"{latest['version']}-{latest['release']}"
                )

                if comparison > 0:
                    # rpm is newer
                    latest = rpm
                elif comparison == 0:
                    # Same version, prefer x86_64
                    if rpm['arch'] == 'x86_64' and latest['arch'] != 'x86_64':
                        latest = rpm
                    elif rpm['arch'] == 'x86_64' and latest['arch'] == 'x86_64':
                        # Both x86_64, keep first one
                        pass
                    elif rpm['arch'] != 'x86_64' and latest['arch'] != 'x86_64':
                        # Neither is x86_64, prefer noarch if available
                        if rpm['arch'] == 'noarch':
                            latest = rpm

            latest_rpms.append(latest)

        return latest_rpms

    def get_rpm_list(self) -> List[Dict[str, str]]:
        """Get list of available RPMs from UBI 9 repositories"""
        print("Fetching available RPMs from UBI 9 repositories...")
        print("(This may take a minute as it queries all available packages)")

        # Use yum list available to get all packages
        # Format: package-name.arch  version-release  repository
        output = self.container_runner.run_command(
            self.ubi_image,
            ["sh", "-c", "yum list available 2>/dev/null || yum list all 2>/dev/null"]
        )

        all_rpms = []
        for line in output.strip().split('\n'):
            line = line.strip()
            if not line or line.startswith('Available') or line.startswith('Installed') or line.startswith('Last'):
                continue

            # Skip header lines and repo update messages
            if 'packages' in line.lower() or 'subscription' in line.lower():
                continue

            # Parse format: package-name.arch  version-release  repo
            # Use split with maxsplit to handle package names with spaces
            parts = line.split(None, 2)
            if len(parts) < 2:
                continue

            pkg_with_arch = parts[0]
            version_release = parts[1]

            # Split package name and architecture
            if '.' in pkg_with_arch:
                pkg_name, arch = pkg_with_arch.rsplit('.', 1)
            else:
                # No architecture specified, skip
                continue

            # Split version and release
            if '-' in version_release:
                # Version-release format, find last '-' to split
                version_parts = version_release.rsplit('-', 1)
                if len(version_parts) == 2:
                    version, release = version_parts
                else:
                    version = version_release
                    release = ''
            else:
                version = version_release
                release = ''

            all_rpms.append({
                'name': pkg_name,
                'version': version,
                'release': release,
                'arch': arch
            })

        print(f"Found {len(all_rpms)} total available RPMs")

        # Filter to latest versions with x86_64 preference
        latest_rpms = self._filter_latest_rpms(all_rpms)

        print(f"Filtered to {len(latest_rpms)} latest RPMs (with x86_64 preference)")

        # Filter out non-container packages
        container_rpms = self._filter_container_packages(latest_rpms)
        print(f"Filtered to {len(container_rpms)} container-relevant RPMs")

        # Filter out Red Hat-specific packages
        non_rh_rpms, removed_rh = self._filter_redhat_specific(container_rpms)
        print(f"Removed {len(removed_rh)} Red Hat-specific RPMs")
        print(f"Remaining: {len(non_rh_rpms)} RPMs")

        # Filter out Apache modules, 64-bit variants, SELinux, filesystem, iSCSI and legacy packages
        filtered_rpms, removed_apache = self._filter_apache_and_variants(non_rh_rpms)
        print(f"Removed {len(removed_apache)} Apache modules, 64-bit variants, -selinux, -filesystem, iscsi, and legacy RPMs")
        print(f"Remaining: {len(filtered_rpms)} RPMs")

        # Filter out non-open source and EOL packages
        open_source_rpms, removed_proprietary = self._filter_non_open_source(filtered_rpms)
        print(f"Removed {len(removed_proprietary)} non-open source and EOL RPMs")
        print(f"Remaining: {len(open_source_rpms)} open source, supported RPMs")

        return open_source_rpms

    def _filter_container_packages(self, rpms: List[Dict[str, str]]) -> List[Dict[str, str]]:
        """Filter out packages not typically used in containers"""
        # Patterns for packages to exclude (GUI, desktop, printing, etc.)
        exclude_patterns = [
            # Desktop/GUI
            'gtk', 'qt5', 'gnome', 'kde', 'xorg', 'X11', 'wayland', 'mesa',
            'adwaita', 'hicolor', 'icon-theme', 'desktop', 'gdk-pixbuf',
            # Printing
            'cups', 'ghostscript', 'printer',
            # Display/Graphics (non-essential)
            'libX', 'libGL', 'vulkan', 'libdrm', 'libva', 'libvdpau',
            # Audio
            'pulseaudio', 'alsa', 'sound', 'audio', 'gstreamer',
            # Fonts (usually not needed in containers)
            '-fonts', 'fontconfig', 'fontenc', 'font-',
            # Hardware-specific
            'pciutils', 'usbutils', 'bluez', 'wireless',
            # Trackers/indexers
            'tracker', 'baloo',
            # Screensavers
            'screensaver', 'xscreensaver',
            # Session management
            'session-', 'polkit', 'udisks', 'upower',
        ]

        # Specific packages to exclude
        exclude_exact = {
            'at-spi2-atk', 'at-spi2-core', 'colord', 'colord-libs',
            'dconf', 'gsettings-desktop-schemas', 'gvfs-client',
            'flatpak-session-helper', 'flatpak-spawn',
            'shared-mime-info', 'xkeyboard-config', 'iso-codes',
        }

        filtered = []
        for rpm in rpms:
            name = rpm['name']

            # Check exact exclusions
            if name in exclude_exact:
                continue

            # Check pattern exclusions
            should_exclude = False
            for pattern in exclude_patterns:
                if pattern in name.lower():
                    should_exclude = True
                    break

            if not should_exclude:
                filtered.append(rpm)

        return filtered

    def _filter_redhat_specific(self, rpms: List[Dict[str, str]]) -> tuple[List[Dict[str, str]], List[str]]:
        """Filter out Red Hat-specific packages and return both filtered list and removed names"""

        # Patterns for Red Hat-specific packages
        # NOTE: Toolsets (gcc-toolset-, llvm-toolset, etc.) are NOT filtered - they'll be matched to APK equivalents
        rh_patterns = [
            'redhat-',           # Red Hat branding
            'rhel-',             # RHEL-specific
            'subscription-',     # Subscription manager
            'insights-',         # Red Hat Insights
        ]

        # Exact package names to exclude
        rh_exact = {
            # Build and packaging tools (Red Hat-specific)
            'redhat-rpm-config',
            'rpm-build',
            'rpm-build-libs',
            'rpm-sign-libs',
            'rpm-plugin-selinux',
            'rpm-plugin-systemd-inhibit',
            'rpmdevtools',
            'rpmlint',
            'scl-utils',
            'scl-utils-build',

            # Red Hat branding
            'redhat-logos-httpd',

            # Macros (Red Hat-specific)
            'kernel-srpm-macros',
            'efi-srpm-macros',
            'ghc-srpm-macros',
            'go-srpm-macros',
            'ocaml-srpm-macros',
            'openblas-srpm-macros',
            'perl-srpm-macros',
            'python-srpm-macros',
            'qt5-srpm-macros',
            'rust-srpm-macros',

            # SELinux policies (Red Hat-specific configurations)
            'selinux-policy',
            'selinux-policy-targeted',
            'container-selinux',

            # Package managers (RPM-specific, not APK)
            'dnf-automatic',
            'dnf-plugins-core',
            'yum-utils',
            'microdnf',

            # Init system (systemd is RHEL-centric in this context)
            'initscripts',
            'initscripts-rename-device',
            'initscripts-service',

            # Red Hat-specific system tools
            'librhsm',

            # Annobin (Red Hat security tool)
            'annobin',

            # Software Collections (utilities only, not toolsets themselves)
            'scl-utils',
            'scl-utils-build',

            # SRPM macros
            'fonts-srpm-macros',
            'pyproject-srpm-macros',

            # Note: go-srpm-macros, rust-srpm-macros, etc. stay in, but toolsets (go-toolset, rust-toolset) are NOT excluded
        }

        filtered = []
        removed = []

        for rpm in rpms:
            name = rpm['name']
            should_exclude = False

            # Check if "rpm" is in the package name (RPM-specific packages)
            if 'rpm' in name.lower():
                should_exclude = True
            # Check if "-src" is in the package name (source packages)
            elif '-src' in name.lower():
                should_exclude = True
            # Check exact matches
            elif name in rh_exact:
                should_exclude = True
            else:
                # Check pattern matches
                for pattern in rh_patterns:
                    if name.startswith(pattern) or pattern in name:
                        should_exclude = True
                        break

            if should_exclude:
                removed.append(name)
            else:
                filtered.append(rpm)

        return filtered, removed

    def _filter_apache_and_variants(self, rpms: List[Dict[str, str]]) -> tuple[List[Dict[str, str]], List[str]]:
        """Filter out Apache modules (mod_*), 64-bit variants, -selinux, -filesystem, iscsi, and legacy packages"""
        filtered = []
        removed = []

        for rpm in rpms:
            name = rpm['name']
            should_exclude = False

            # Filter Apache modules (mod_*)
            if name.startswith('mod_'):
                should_exclude = True
            # Filter packages ending in 64 or 64_ (64-bit architecture variants)
            # But NOT packages where 64 is part of the name like Base64, SHA256, etc.
            elif name.endswith('64') or name.endswith('64_'):
                # Exclude common false positives (Base64, SHA256, etc.)
                if not any(x in name.lower() for x in ['base64', 'sha256', 'sha512', 'md5']):
                    should_exclude = True
            # Filter packages ending in -selinux (SELinux-specific)
            elif name.endswith('-selinux'):
                should_exclude = True
            # Filter packages ending in -filesystem (filesystem layouts)
            elif name.endswith('-filesystem'):
                should_exclude = True
            # Filter iSCSI packages (iscsi*)
            elif name.startswith('iscsi'):
                should_exclude = True
            # Filter legacy packages (contains 'legacy')
            elif 'legacy' in name.lower():
                should_exclude = True
            # Filter DNF packages (contains 'dnf')
            elif 'dnf' in name.lower():
                should_exclude = True

            if should_exclude:
                removed.append(name)
            else:
                filtered.append(rpm)

        return filtered, removed

    def _filter_non_open_source(self, rpms: List[Dict[str, str]]) -> tuple[List[Dict[str, str]], List[str]]:
        """Filter out non-open source and EOL packages"""

        # Patterns for non-open source packages
        proprietary_patterns = [
            'adobe-',            # Adobe proprietary products
        ]

        # Exact non-open source packages
        proprietary_exact = {
            # Adobe products (proprietary)
            'adobe-mappings-cmap',
            'adobe-mappings-cmap-deprecated',
            'adobe-mappings-pdf',
            'adobe-source-code-pro-fonts',
        }

        # EOL software versions that should be filtered
        eol_patterns = [
            # .NET/ASP.NET 6.0 (EOL November 2024)
            'aspnetcore-runtime-6.0',
            'aspnetcore-targeting-pack-6.0',
            'dotnet-apphost-pack-6.0',
            'dotnet-hostfxr-6.0',
            'dotnet-runtime-6.0',
            'dotnet-sdk-6.0',
            'dotnet-targeting-pack-6.0',
            'dotnet-templates-6.0',

            # .NET/ASP.NET 7.0 (EOL May 2024)
            'aspnetcore-runtime-7.0',
            'aspnetcore-targeting-pack-7.0',
            'dotnet-apphost-pack-7.0',
            'dotnet-hostfxr-7.0',
            'dotnet-runtime-7.0',
            'dotnet-sdk-7.0',
            'dotnet-targeting-pack-7.0',
            'dotnet-templates-7.0',

            # .NET host infrastructure (all versions - no direct APK equivalents)
            'dotnet-host',
            'dotnet-hostfxr-8.0',
            'dotnet-hostfxr-9.0',
            'dotnet-hostfxr-10.0',

            # Note: Java 8 (OpenJDK 8) is NOT EOL and has Chainguard equivalents
            # Note: Python 3.11 is NOT EOL (EOL October 2027) and is still widely used
        ]

        filtered = []
        removed = []

        for rpm in rpms:
            name = rpm['name']
            should_exclude = False

            # Check EOL packages
            if name in eol_patterns:
                should_exclude = True
            # Check proprietary exact matches
            elif name in proprietary_exact:
                should_exclude = True
            else:
                # Check proprietary patterns
                for pattern in proprietary_patterns:
                    if name.startswith(pattern):
                        should_exclude = True
                        break

            if should_exclude:
                removed.append(name)
            else:
                filtered.append(rpm)

        return filtered, removed


class APKMatcher:
    """Find matching Chainguard APKs"""

    def __init__(self, container_runner: ContainerRunner):
        self.container_runner = container_runner
        # Using Chainguard's Wolfi base image which has apk
        self.chainguard_image = "cgr.dev/chainguard/wolfi-base:latest"
        self.apk_cache = None
        self.apk_cache_lower = None
        self.versioned_index = None  # Pre-built index for versioned packages

    def _build_apk_cache(self) -> Dict[str, Dict[str, str]]:
        """Build a cache of available APKs using wolfi-package-status"""
        print("Fetching available APKs from Chainguard Wolfi...")

        # Try using wolfi-package-status first (more comprehensive)
        try:
            # Get auth token
            token_result = subprocess.run(
                ["chainctl", "auth", "token", "--audience", "apk.cgr.dev"],
                capture_output=True,
                text=True,
                check=True
            )
            token = token_result.stdout.strip()

            # Get package list
            result = subprocess.run(
                ["wolfi-package-status", "--auth-token", token],
                capture_output=True,
                text=True,
                check=True
            )
            output = result.stdout

            apk_cache = {}
            apk_cache_lower = {}  # Case-insensitive lookup

            # Parse output format: "package-name version ... in wolfi os repository"
            for line in output.strip().split('\n'):
                if not line:
                    continue

                # Extract just the package name (first word)
                parts = line.split()
                if len(parts) > 0:
                    pkg_name = parts[0]

                    apk_cache[pkg_name] = {
                        'name': pkg_name,
                        'version': parts[2] if len(parts) > 2 else 'unknown'
                    }

                    # Also store lowercase version for case-insensitive lookup
                    apk_cache_lower[pkg_name.lower()] = apk_cache[pkg_name]

            print(f"Found {len(apk_cache)} APKs in Chainguard Wolfi (via wolfi-package-status)")

        except (subprocess.CalledProcessError, FileNotFoundError) as e:
            # Fallback to apk search if wolfi-package-status is not available
            print(f"  Warning: wolfi-package-status not available ({e}), falling back to apk search")

            output = self.container_runner.run_command(
                self.chainguard_image,
                ["sh", "-c", "apk search -a --no-cache -q | sort | uniq"]
            )

            apk_cache = {}
            apk_cache_lower = {}

            for line in output.strip().split('\n'):
                if not line:
                    continue

                pkg_name = line.strip()

                apk_cache[pkg_name] = {
                    'name': pkg_name,
                    'version': 'unknown'
                }

                apk_cache_lower[pkg_name.lower()] = apk_cache[pkg_name]

            print(f"Found {len(apk_cache)} APKs in Chainguard Wolfi (via apk search)")

        return apk_cache, apk_cache_lower

    def find_match(self, rpm: Dict[str, str]) -> Optional[Dict[str, str]]:
        """Find matching APK for an RPM with creative matching strategies"""
        if self.apk_cache is None:
            self.apk_cache, self.apk_cache_lower = self._build_apk_cache()

        rpm_name = rpm['name']

        # Try exact name match first (case-sensitive)
        if rpm_name in self.apk_cache:
            return self.apk_cache[rpm_name]

        # Try exact name match (case-insensitive)
        if rpm_name.lower() in self.apk_cache_lower:
            return self.apk_cache_lower[rpm_name.lower()]

        # Try all alternative matching strategies
        alternatives = self._generate_alternatives(rpm_name)

        for alt in alternatives:
            if not alt:
                continue
            # Try case-sensitive first
            if alt in self.apk_cache:
                return self.apk_cache[alt]
            # Then case-insensitive
            if alt.lower() in self.apk_cache_lower:
                return self.apk_cache_lower[alt.lower()]

        # Try versioned variants (foo -> foo-21, foo-20, etc., pick highest version)
        versioned_match = self._find_versioned_variant(rpm_name)
        if versioned_match:
            return versioned_match

        # Fuzzy matching as last resort - find APKs containing the RPM base name
        base_name = self._get_base_name(rpm_name)
        if len(base_name) >= 4:  # Only for names with 4+ chars to avoid false matches
            fuzzy_match = self._fuzzy_search(base_name)
            if fuzzy_match:
                return fuzzy_match

        return None

    def _get_base_name(self, rpm_name: str) -> str:
        """Extract base name from RPM package name"""
        # Remove common suffixes
        name = rpm_name
        for suffix in ['-devel', '-libs', '-tools', '-utils', '-doc', '-docs', '-common']:
            if name.endswith(suffix):
                name = name[:-len(suffix)]
                break
        # Remove version numbers
        name = re.sub(r'-?\d+\.?\d*$', '', name)
        return name

    def _fuzzy_search(self, base_name: str) -> Optional[Dict[str, str]]:
        """Find APK package that closely matches the base name (case-insensitive)"""
        base_lower = base_name.lower()

        # Look for exact substring match (case-insensitive)
        if base_lower in self.apk_cache_lower:
            return self.apk_cache_lower[base_lower]

        # Look for APKs that start with the base name (case-insensitive)
        candidates = [k for k in self.apk_cache_lower.keys() if k.startswith(base_lower)]
        if candidates:
            # Prefer shorter names (closer match)
            candidates.sort(key=len)
            return self.apk_cache_lower[candidates[0]]

        # Look for APKs that contain the base name (case-insensitive)
        candidates = [k for k in self.apk_cache_lower.keys() if base_lower in k]
        if candidates:
            # Prefer names where base is at the start
            for candidate in candidates:
                if candidate.startswith(base_lower):
                    return self.apk_cache_lower[candidate]
            # Otherwise return shortest match
            candidates.sort(key=len)
            return self.apk_cache_lower[candidates[0]]

        return None

    def _find_versioned_variant(self, rpm_name: str) -> Optional[Dict[str, str]]:
        """Find versioned APK variants (foo -> foo-21, lua -> lua5.4, etc.)
        Returns the APK with the highest version number"""
        import re

        # Look for packages matching {rpm_name}-{number} or {rpm_name}{number}.{number}
        # e.g., lld -> lld-21, lua -> lua5.4
        candidates = []

        for apk_name in self.apk_cache.keys():
            # Pattern 1: {name}-{version} (e.g., lld-21)
            match = re.match(rf'^{re.escape(rpm_name)}-(\d+)$', apk_name)
            if match:
                version = int(match.group(1))
                candidates.append((version, 0, apk_name))
                continue

            # Pattern 2: {name}{major}.{minor} (e.g., lua5.4, python3.12)
            match = re.match(rf'^{re.escape(rpm_name)}(\d+)\.(\d+)$', apk_name)
            if match:
                major = int(match.group(1))
                minor = int(match.group(2))
                # Use tuple for proper version comparison
                candidates.append((major, minor, apk_name))
                continue

            # Pattern 3: {name}{version} (e.g., python3, ruby3)
            match = re.match(rf'^{re.escape(rpm_name)}(\d+)$', apk_name)
            if match:
                version = int(match.group(1))
                candidates.append((version, 0, apk_name))
                continue

        if not candidates:
            return None

        # Sort by version (highest first)
        candidates.sort(reverse=True)
        latest_apk = candidates[0][2]

        return self.apk_cache[latest_apk]

    def _generate_alternatives(self, rpm_name: str) -> List[str]:
        """Generate all possible APK name alternatives for an RPM"""
        alternatives = []

        # Strategy 1: Direct tool/package equivalents
        tool_mappings = {
            # Package managers (note: some RPM-specific ones filtered out earlier)
            'rpm-libs': 'apk-tools',
            # Network
            'NetworkManager': 'network-manager',
            'NetworkManager-libnm': 'network-manager',
            # Web servers
            'httpd': 'apache2',
            'httpd-core': 'apache2',
            'httpd-tools': 'apache2-utils',
            'httpd-devel': 'apache2-dev',
            # Databases
            'mariadb': 'mariadb-client',
            'mariadb-common': 'mariadb-common',
            'mysql': 'mariadb-client',
            'mysql-libs': 'mariadb-connector-c',
            'mysql-common': 'mariadb-common',
            'postgresql': 'postgresql-client',
            'postgresql-private-libs': 'libpq',
            # Utilities
            'net-tools': 'net-tools-deprecated',
            'coreutils-common': 'coreutils',
            'util-linux-user': 'util-linux',
            'procps-ng': 'procps',
            # APR
            'apr': 'apr-util',
            'apr-devel': 'apr-util-dev',
            # Augeas
            'augeas-libs': 'augeas',
            # Bind
            'bind-libs': 'bind',
            'bind-utils': 'bind-tools',
            'bind-license': 'bind',
            # Crypto
            'compat-openssl11': 'openssl',
            'openssl-libs': 'openssl',
            'openssl-devel': 'openssl-dev',
            # System
            'shadow-utils-subid': 'shadow',
            'audit-libs': 'audit',
            'pam': 'linux-pam',
            'libselinux': 'libselinux',
            'libselinux-devel': 'libselinux-dev',
            # Compression
            'bzip2-libs': 'bzip2',
            'xz-libs': 'xz',
            'lz4-libs': 'lz4',
            'libzstd': 'zstd',
            # Build tools
            'gcc-c++': 'g++',
            'binutils-gold': 'binutils',
            'make': 'make',
            # Container tools
            'podman-docker': 'podman',
            'podman-remote': 'podman',
            'containers-common-extra': 'containers-common',
            'containernetworking-plugins': 'cni-plugins',
            'aardvark-dns': 'aardvark-dns',  # Direct match attempt
            # LLVM/Clang
            'clang-libs': 'clang',
            'llvm-libs': 'llvm',
            'compiler-rt': 'compiler-rt',
            # Rust
            'cargo-doc': 'cargo',
            'rust-analysis': 'rust',
            'rust-doc': 'rust',
            'rust-src': 'rust',
            'clippy': 'rust',
            'rustfmt': 'rust',
            # Go
            'golang-bin': 'go',
            'golang': 'go',
            'golang-docs': 'go',
            'golang-misc': 'go',
            'golang-src': 'go',
            'golang-tests': 'go',
            # Node.js
            'nodejs-libs': 'nodejs',
            'nodejs-docs': 'nodejs',
            'nodejs-full-i18n': 'nodejs',
            # Perl
            'perl-interpreter': 'perl',
            'perl-libs': 'perl',
            'perl-macros': 'perl',
            # Various libs
            'dbus-libs': 'dbus',
            'dbus-tools': 'dbus',
            'dbus-daemon': 'dbus',
            'elfutils-libs': 'elfutils',
            'elfutils-libelf': 'elfutils',
            'file-libs': 'file',
            'gdbm-libs': 'gdbm',
            'keyutils-libs': 'keyutils',
            'kmod-libs': 'kmod',
            'libacl': 'acl',
            'libattr': 'attr',
            'libblkid': 'util-linux',
            'libcap': 'libcap',
            'libcom_err': 'e2fsprogs',
            'libfdisk': 'util-linux',
            'libmount': 'util-linux',
            'libsmartcols': 'util-linux',
            'libuuid': 'util-linux',
            'ncurses-libs': 'ncurses',
            'ncurses-c++-libs': 'ncurses',
            'pcre-cpp': 'pcre',
            'pcre-utf16': 'pcre',
            'pcre-utf32': 'pcre',
            'pcre2-utf16': 'pcre2',
            'pcre2-utf32': 'pcre2',
            'readline': 'readline',
            'sqlite-libs': 'sqlite',
            # Debugger
            'gdb-headless': 'gdb',
            # Archive tools
            'bsdtar': 'libarchive-tools',
            # C preprocessor
            'cpp': 'gcc',
            # Cyrus SASL
            'cyrus-sasl-lib': 'cyrus-sasl',
            'cyrus-sasl-gssapi': 'cyrus-sasl',
            'cyrus-sasl-plain': 'cyrus-sasl',
            # elfutils
            'elfutils-debuginfod-client': 'elfutils',
            # hunspell dictionaries
            'hunspell-en-US': 'hunspell-dictionary-en',
            'hunspell-en': 'hunspell-dictionary-en',
            # Git
            'git-core': 'git',
            # Vim
            'vim-common': 'vim',
            # Nginx
            'nginx-core': 'nginx-mainline',
            # Lua
            'lua-libs': 'lua5.4-libs',
            # GCC compilers
            'gcc-c++': 'gcc',
            'gcc-gfortran': 'gfortran',
            # PHP
            'php': 'php-8.5',
            # Python
            'python3-debug': 'py3-debugpy',
            # Ruby base packages
            'rubygems': 'ruby-3.4',
            'rubygems-devel': 'ruby-3.4-dev',
            # GCC toolset base
            'gcc-toolset-15': 'gcc',
            # OpenSSH
            'openssh-clients': 'openssh-client',
            # Keyboard
            'kbd-misc': 'kbd',
            # Libtool
            'libtool-ltdl': 'libtool',
        }

        if rpm_name in tool_mappings:
            alternatives.append(tool_mappings[rpm_name])

        # Strategy 2: .NET/ASP.NET packages (aspnetcore-runtime-10.0 -> aspnet-10-runtime)
        aspnet_match = re.match(r'^aspnetcore-(.+?)-(\d+)\.(\d+)$', rpm_name)
        if aspnet_match:
            component = aspnet_match.group(1)
            major = aspnet_match.group(2)
            # Try: aspnet-{major}-{component}
            alternatives.append(f'aspnet-{major}-{component}')
            alternatives.append(f'aspnet{major}-{component}')
            alternatives.append(f'dotnet-{major}-{component}')
            alternatives.append(f'dotnet{major}-{component}')

        # Strategy 3: .NET SDK/runtime packages
        dotnet_match = re.match(r'^dotnet-(.+?)-(\d+)\.(\d+)$', rpm_name)
        if dotnet_match:
            component = dotnet_match.group(1)
            major = dotnet_match.group(2)
            alternatives.append(f'dotnet-{major}-{component}')
            alternatives.append(f'dotnet{major}-{component}')
            alternatives.append(f'dotnet-{component}-{major}')
            # Special case for dotnet-sdk-aot-10.0 -> dotnet-10-aot
            if component == 'sdk-aot':
                alternatives.append(f'dotnet-{major}-aot')

        # Strategy 4: GCC toolsets (gcc-toolset-12-gcc -> gcc-12, gcc-12-default, etc.)
        # First check for base toolset package (gcc-toolset-12 without component)
        gcc_base_match = re.match(r'^gcc-toolset-(\d+)$', rpm_name)
        if gcc_base_match:
            version = gcc_base_match.group(1)
            alternatives.append(f'gcc-{version}')
            alternatives.append(f'gcc-{version}-default')

        gcc_match = re.match(r'^gcc-toolset-(\d+)-(.+)$', rpm_name)
        if gcc_match:
            version = gcc_match.group(1)
            component = gcc_match.group(2)

            # Map to gcc-{version} and gcc-{version}-default
            if component == 'gcc':
                alternatives.append(f'gcc-{version}')
                alternatives.append(f'gcc-{version}-default')
                alternatives.append('gcc')  # Fallback to default
            elif component == 'gcc-c++':
                alternatives.append(f'g++-{version}')
                alternatives.append(f'gcc-{version}')  # C++ is part of gcc package
            elif component == 'gcc-gfortran':
                alternatives.append(f'gfortran-{version}')
                alternatives.append(f'gcc-{version}')  # Fortran might be part of gcc
            elif component == 'binutils':
                alternatives.append(f'binutils')  # Usually no versioned binutils
            elif component == 'gdb':
                alternatives.append('gdb')
            elif component.startswith('lib'):
                # Library packages (libstdc++, libasan, etc.) - try gcc package
                alternatives.append(f'gcc-{version}')
                alternatives.append(f'{component}')
            elif component in ['runtime', 'build']:
                # Meta packages - map to main gcc
                alternatives.append(f'gcc-{version}')
            else:
                # Other components
                alternatives.append(f'{component}-{version}')
                alternatives.append(f'gcc-{version}')

        # Strategy 4b: LLVM toolset (llvm-toolset -> llvm-18, llvm15-tools)
        if rpm_name == 'llvm-toolset':
            # Try various LLVM versions
            for ver in ['21', '20', '19', '18', '17', '16', '15']:
                alternatives.append(f'llvm{ver}')
                alternatives.append(f'llvm-{ver}')
                alternatives.append(f'llvm{ver}-tools')
                alternatives.append(f'llvm-{ver}-tools')

        # Strategy 4c: Rust toolset (rust-toolset -> rust-1.91, rust)
        if rpm_name == 'rust-toolset':
            alternatives.append('rust')
            # Try recent versions
            for minor in range(91, 80, -1):
                alternatives.append(f'rust-1.{minor}')

        # Strategy 4d: Go toolset (go-toolset -> go-1.23, go)
        if rpm_name == 'go-toolset':
            alternatives.append('go')
            # Try recent versions
            for minor in range(25, 19, -1):
                alternatives.append(f'go-1.{minor}')

        # Strategy 5: Versioned -devel packages (clang-devel -> clang-18-dev, clang-17-dev, etc.)
        if rpm_name.endswith('-devel'):
            base = rpm_name[:-6]  # Remove '-devel'

            # Try base-dev first
            alternatives.append(f'{base}-dev')

            # For compilers/tools, try with common version numbers
            if base in ['clang', 'llvm', 'gcc', 'python', 'perl', 'ruby', 'php', 'node', 'nodejs']:
                for ver in ['18', '17', '16', '15', '14', '13', '12', '11', '10', '9', '8', '7', '3']:
                    alternatives.append(f'{base}-{ver}-dev')
                    alternatives.append(f'{base}{ver}-dev')

        # Strategy 6: -libs suffix variations
        if rpm_name.endswith('-libs'):
            base = rpm_name[:-5]
            alternatives.append(base)  # Remove -libs
            alternatives.append(f'lib{base}')  # Add lib prefix
            alternatives.append(f'{base}-libs')  # Keep as-is

        # Strategy 7: -tools suffix
        if rpm_name.endswith('-tools'):
            base = rpm_name[:-6]
            alternatives.append(base)
            alternatives.append(f'{base}-utils')
            alternatives.append(f'{base}-tools')

        # Strategy 8: lib prefix handling
        if rpm_name.startswith('lib') and len(rpm_name) > 3:
            without_lib = rpm_name[3:]
            alternatives.append(without_lib)

            # If it ends in -devel, try without lib and with -dev
            if rpm_name.endswith('-devel'):
                base = rpm_name[3:-6]  # Remove 'lib' and '-devel'
                alternatives.append(f'{base}-dev')

        # Strategy 9: Python version variations (python3.11-requests -> py3.11-requests)
        python_match = re.match(r'^python(\d+)\.(\d+)(.*)$', rpm_name)
        if python_match:
            major = python_match.group(1)
            minor = python_match.group(2)
            suffix = python_match.group(3)

            # Primary pattern: py3.11-package (most common in Chainguard)
            alternatives.append(f'py{major}.{minor}{suffix}')

            # Alternative patterns
            alternatives.append(f'python-{major}.{minor}{suffix}')
            alternatives.append(f'python{major}.{minor}{suffix}')
            alternatives.append(f'py{major}{suffix}')
            alternatives.append(f'python{major}{suffix}')

            if not suffix:
                alternatives.append('python3')
                alternatives.append('python')

        # Strategy 10: Java OpenJDK versions (java-17-openjdk -> openjdk-17, java-1.8.0-openjdk -> openjdk-8)
        java_match = re.match(r'^java-(\d+)-openjdk(.*)$', rpm_name)
        if java_match:
            version = java_match.group(1)
            suffix = java_match.group(2)
            alternatives.append(f'openjdk-{version}{suffix}')
            alternatives.append(f'openjdk{version}{suffix}')
            alternatives.append(f'java-{version}{suffix}')
            # -headless suffix usually maps to base package
            if suffix == '-headless':
                alternatives.append(f'openjdk-{version}')
                alternatives.append(f'openjdk-{version}-jre')
            elif suffix == '-devel':
                alternatives.append(f'openjdk-{version}-default-jdk')
                alternatives.append(f'openjdk-{version}-jdk')

        # Special handling for Java 8 (version 1.8.0)
        java8_match = re.match(r'^java-1\.8\.0-openjdk(.*)$', rpm_name)
        if java8_match:
            suffix = java8_match.group(1)
            alternatives.append(f'openjdk-8{suffix}')
            alternatives.append('openjdk-8')
            alternatives.append('openjdk-8-jre')
            alternatives.append('openjdk-8-default-jvm')
            alternatives.append('openjdk-8-default-jdk')
            if suffix == '-headless':
                alternatives.append('openjdk-8')
            elif suffix == '-devel':
                alternatives.append('openjdk-8-default-jdk')
                alternatives.append('openjdk-8-dev')

        # Strategy 11: Perl modules (perl-Something -> perl-something)
        if rpm_name.startswith('perl-'):
            alternatives.append(rpm_name.lower())
            # Try without perl- prefix
            alternatives.append(rpm_name[5:].lower())

        # Strategy 11b: Ruby gems (rubygem-bundler -> ruby3.4-bundler)
        if rpm_name.startswith('rubygem-'):
            gem_name = rpm_name[8:]  # Remove 'rubygem-'
            # Primary: Try ruby3.4-* (Chainguard uses versioned ruby packages)
            alternatives.append(f'ruby3.4-{gem_name}')
            alternatives.append(f'ruby3.3-{gem_name}')
            alternatives.append(f'ruby3.2-{gem_name}')
            # Fallback: Try older patterns
            alternatives.append(f'ruby-{gem_name}')
            alternatives.append(gem_name)
            # Common Ruby gems
            if gem_name in ['bundler', 'rake', 'rdoc', 'irb']:
                alternatives.append('ruby')  # Part of ruby package

        # Strategy 11c: Python modules (python3-setuptools -> py3-setuptools)
        if rpm_name.startswith('python3-'):
            module_name = rpm_name[8:]
            alternatives.append(f'py3-{module_name}')
            alternatives.append(f'python-{module_name}')
            alternatives.append(module_name)

        # Strategy 11d: PHP modules (php-xml -> php-8.3-xml, etc.)
        if rpm_name.startswith('php-'):
            module_name = rpm_name[4:]
            # Try with common PHP versions
            for ver in ['8.3', '8.2', '8.1', '8.0', '7.4']:
                alternatives.append(f'php-{ver}-{module_name}')
                alternatives.append(f'php{ver}-{module_name}')
            alternatives.append(f'php-{module_name}')

        # Strategy 11e: PHP PECL extensions
        if rpm_name.startswith('php-pecl-'):
            ext_name = rpm_name[9:]
            alternatives.append(f'php-{ext_name}')
            alternatives.append(f'php-pecl-{ext_name}')
            for ver in ['8.3', '8.2', '8.1']:
                alternatives.append(f'php-{ver}-{ext_name}')

        # Strategy 12: Container tools
        container_mappings = {
            'podman-docker': 'podman',
            'podman-remote': 'podman',
            'skopeo': 'skopeo',
            'buildah': 'buildah',
            'containers-common': 'containers-common',
        }
        if rpm_name in container_mappings:
            alternatives.append(container_mappings[rpm_name])

        # Strategy 13: Remove version numbers from name and try plain name
        # (e.g., compat-openssl11 -> openssl)
        no_ver = re.sub(r'\d+', '', rpm_name)
        if no_ver != rpm_name:
            alternatives.append(no_ver)
            # Also try with -dev if original had -devel
            if rpm_name.endswith('-devel'):
                alternatives.append(no_ver.replace('-devel', '-dev'))

        # Strategy 14: Compiler runtime libraries
        if rpm_name in ['libgcc', 'libstdc++', 'libgomp', 'libgfortran']:
            alternatives.append(rpm_name)
            alternatives.append(f'{rpm_name}-libs')

        # Strategy 15: Common package name differences
        name_mappings = {
            'procps-ng': 'procps',
            'util-linux-user': 'util-linux',
            'shadow-utils-subid': 'shadow',
            'kernel-headers': 'linux-headers',
            'glibc-headers': 'glibc-dev',
            'glibc-devel': 'glibc-dev',
            'glibc-static': 'glibc-static',
            'man-db': 'man-db',
            'cronie': 'cronie',
            'cronie-anacron': 'cronie',
        }
        if rpm_name in name_mappings:
            alternatives.append(name_mappings[rpm_name])

        # Strategy 16: FFTW libs (fftw-libs-double -> fftw-double-libs)
        fftw_match = re.match(r'^fftw-libs-(.+)$', rpm_name)
        if fftw_match:
            precision = fftw_match.group(1)
            alternatives.append(f'fftw-{precision}-libs')

        # Strategy 17: Nginx modules (nginx-mod-http-perl -> nginx-mainline-mod-http_perl)
        nginx_mod_match = re.match(r'^nginx-mod-(.+)$', rpm_name)
        if nginx_mod_match:
            module = nginx_mod_match.group(1)
            # Convert dashes to underscores in module name (Chainguard naming)
            module_underscore = module.replace('-', '_')
            alternatives.append(f'nginx-mainline-mod-{module_underscore}')
            alternatives.append(f'nginx-mainline-mod-{module}')

        # Strategy 18: Fuzzy matching - check if APK name contains RPM base name
        # This is done as a last resort in the match function

        return alternatives


class CSVGenerator:
    """Generate CSV output"""

    @staticmethod
    def write_csv(data: List[Dict[str, str]], output_file: str, show_all: bool = False):
        """Write mapping data to CSV

        Args:
            data: List of RPM to APK mappings
            output_file: Path to output CSV file
            show_all: If False, only include matched RPMs; if True, include all RPMs
        """
        print(f"Writing results to {output_file}...")

        # Filter out Perl, PHP, and Ruby gem packages with no matches
        filtered_data = []
        perl_removed = 0
        php_removed = 0
        ruby_removed = 0
        unmatched_removed = 0

        for row in data:
            rpm_name = row.get('rpm_name', '')
            apk_name = row.get('apk_name', '')

            # Skip Perl packages with no match
            if rpm_name.startswith('perl-') and not apk_name:
                perl_removed += 1
                continue
            # Skip PHP packages with no match
            if rpm_name.startswith('php') and not apk_name:
                php_removed += 1
                continue
            # Skip Ruby gem packages with no match
            if rpm_name.startswith('rubygem-') and not apk_name:
                ruby_removed += 1
                continue

            # If show_all is False, skip all other unmatched packages
            if not show_all and not apk_name:
                unmatched_removed += 1
                continue

            filtered_data.append(row)

        if perl_removed > 0:
            print(f"Excluded {perl_removed} unmatched Perl packages from CSV")
        if php_removed > 0:
            print(f"Excluded {php_removed} unmatched PHP packages from CSV")
        if ruby_removed > 0:
            print(f"Excluded {ruby_removed} unmatched Ruby gem packages from CSV")
        if not show_all and unmatched_removed > 0:
            print(f"Excluded {unmatched_removed} other unmatched packages from CSV (use --show-all to include)")

        fieldnames = ['rpm_name', 'apk_name']

        with open(output_file, 'w', newline='') as csvfile:
            writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(filtered_data)

        print(f"CSV written successfully")


def main():
    parser = argparse.ArgumentParser(
        description='Map Red Hat UBI 9 RPMs to Chainguard APKs'
    )
    parser.add_argument(
        '--output', '-o',
        default='rpm_to_apk_mapping.csv',
        help='Output CSV file (default: rpm_to_apk_mapping.csv)'
    )
    parser.add_argument(
        '--runtime',
        choices=['docker', 'podman'],
        default='docker',
        help='Container runtime to use (default: docker)'
    )
    parser.add_argument(
        '--show-all',
        action='store_true',
        default=False,
        help='Show all RPMs in CSV including unmatched (default: only show matched RPMs)'
    )

    args = parser.parse_args()

    # Initialize components
    container_runner = ContainerRunner(runtime=args.runtime)
    rpm_extractor = RPMExtractor(container_runner)
    apk_matcher = APKMatcher(container_runner)

    # Get RPMs
    rpms = rpm_extractor.get_rpm_list()

    # Match to APKs
    print("Matching RPMs to APKs...")
    results = []
    matched = 0

    for rpm in rpms:
        apk = apk_matcher.find_match(rpm)

        if apk:
            matched += 1
            apk_name = apk['name']
        else:
            apk_name = ''

        results.append({
            'rpm_name': rpm['name'],
            'apk_name': apk_name
        })

    # Generate CSV
    CSVGenerator.write_csv(results, args.output, args.show_all)

    # Print summary
    print("\n" + "="*50)
    print("Summary:")
    print(f"  Total RPMs: {len(rpms)}")
    print(f"  Matched APKs: {matched}")
    print(f"  Unmatched: {len(rpms) - matched}")
    print(f"  Match rate: {matched/len(rpms)*100:.1f}%")
    print("="*50)


if __name__ == "__main__":
    main()
