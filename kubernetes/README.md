# Kubernetes

## List all containers

```sh
kubectl get pods --all-namespaces \
    -o jsonpath="{.items[*].spec['initContainers', 'containers', 'ephemeralContainers'][*].image}" |\
  tr -s '[[:space:]]' '\n' | \
  sort | \
  uniq
```

### Sort by usage

```sh
kubectl get pods --all-namespaces \
    -o jsonpath="{.items[*].spec['initContainers', 'containers', 'ephemeralContainers'][*].image}" |\
  tr -s '[[:space:]]' '\n' | \
  sort | \
  uniq -c | \
  sort -ndr
```
