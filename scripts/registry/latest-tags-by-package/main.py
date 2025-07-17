#!/usr/bin/env python3

import argparse
import re
import requests
from collections import defaultdict
from typing import Dict, List

token = ""

def get_tags(repo: str) -> List[str]:
    parts = repo.split('/')
    registry_host = parts[0]
    repository_path = '/'.join(parts[1:])

    headers = {
        'User-Agent': 'latest-tags-by-package/0.0.0',
        'Accept': '*/*',
    }
    if token:
        headers['Authorization'] = f'Bearer {token}'

    r = requests.get(
            f'https://{registry_host}/v2/{repository_path}/tags/list',
                     headers=headers)

    return r.json()['tags']

def get_manifest(repo: str, tag: str) -> Dict[str, str]:
    parts = repo.split('/')
    registry_host = parts[0]
    repository_path = '/'.join(parts[1:])

    headers = {
        'User-Agent': 'latest-tags-by-package/0.0.0',
        'Accept': '*/*',
    }
    if token:
        headers['Authorization'] = f'Bearer {token}'

    r = requests.get(
            f'https://{registry_host}/v2/{repository_path}/manifests/{tag}',
                     headers=headers)

    return r.json()

def get_latest_tags_by_package(n: int, repo: str) -> Dict[str, List[dict]]:
    """
    Get the latest tags in a repository for each version of the main package.

    The value of n defines how many tags to include for each package.
    """
    tags = get_tags(repo)

    results: Dict[str, List[dict]] = defaultdict(list)

    for tag in tags:
        # Exclude -dev tags
        if re.match(r'^.+-dev$', tag):
            continue

        # Exclude the latest tag
        if tag == 'latest':
            continue

        # Exclude revision tags (i.e {tag}-r0)
        if re.match(r'^.+-r[0-9]+$', tag):
            continue

        # Exclude signatures and attestations
        if re.match(r'^sha256-.+$', tag):
            continue

        # Get the manifest for the tag
        manifest = get_manifest(repo, tag)

        # Skip if manifest has no annotations
        if 'annotations' not in manifest:
            continue

        # Get the created timestamp and the name of the main package from the
        # annotations
        annotations = manifest['annotations']
        package_main = annotations.get('dev.chainguard.package.main')
        created = annotations.get('org.opencontainers.image.created')

        # Aggregate tags by the main package
        if created and package_main:
            results[package_main].append({'created': created, 'tag': tag})

    # Sort the tags by the created timestamp, only include the n most recent for
    # each package
    for package_main in results:
        results[package_main].sort(key=lambda x: x['created'], reverse=True)
        results[package_main] = results[package_main][:n]

    return results

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Find the latest tags in a repository, aggregated by main package.")
    parser.add_argument("--token", "-t", help="Authorization token for registry access")
    parser.add_argument("--number", "-n", type=int, default=5,
        help="The number of tags to return for each package.")
    parser.add_argument("repo")

    args = parser.parse_args()

    token = args.token

    try:
        # Get the latest tags for each main package
        results = get_latest_tags_by_package(args.number, args.repo)

        # Print a section for each package, with the latest tags nested below
        for package_main, tags in results.items():
            print(f'{args.repo} ({package_main})')
            for t in tags:
                tag = t['tag']
                print(f"\t{tag}")

    except Exception as e:
        print(f"Error: {e}")
        exit(1)
