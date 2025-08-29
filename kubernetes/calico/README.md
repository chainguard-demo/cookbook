# Calico

Deploy Calico to a local `kind` cluster using Chainguard Containers.

## Requirements

- `chainctl`
- `crane`
- `curl`
- `docker`
- `helm`
- `kind`
- `kubectl`
- `sed`
- `yq`

## Usage

Run `kind.sh` to create a local Kubernetes cluster.

```
./kind.sh
```

Then, you can run `helm.sh` to deploy Calico with the Helm chart in
[helm-chart](./helm-chart). Provide your org name as the first argument.

```
./helm.sh your.org
```

Or, with bare Kubernetes manifests with `manifests.sh`.

```
./manifests.sh you.org
```
