# Filesystem

## Find image references in yaml files

This script extracts any `image:` fields referenced in yaml files.

```sh
grep -hR "image: .*" --include '*.yaml' | \
  awk '{$1=$1};1' | \
  sed 's/^[- ]*image: //' | \
  sed 's/\s*#.*//' | \
  grep -v "^ko://" | \
  grep -v "^#" | \
  sort | uniq
```

## Find base images from Dockerfiles

This script extracts any "FROM" statements from dockerfiles.

```sh
find . -type f -iname "*dockerfile*" -exec grep -i "^from" {} + | \
  cut -f2 -d' ' | \
  sort | uniq
```
