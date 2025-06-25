# kubelet-credential-provider

This is an example of a local `kind` cluster that uses the
`ServiceAccountTokenForKubeletCredentialProviders` feature to pull images from
`cgr.dev` with assumable identities.

This enables passwordless authentication based on the identity of a pod's
service account.

## Requirements

- [`chainctl`](https://edu.chainguard.dev/chainguard/chainctl-usage/how-to-install-chainctl/)
- [`docker`](https://docs.docker.com/get-started/get-docker/)
- [`jq`](https://github.com/jqlang/jq)
- [`kind`](https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
- [`kubectl`](https://kubernetes.io/docs/tasks/tools/#kubectl)

## Usage

Run `./kind.sh` to create the cluster.

It expects two arguments:

1. Your organization name.
2. An image in the organization to run as an example. It should have a shell.

```
./kind.sh your.org python:latest-dev
```

If the `example` pod comes up as expected, it means the credentials provider
is working as intended.

Once the cluster is up you can run the provider directly to test the output. 

```
ORG=your.org
IMAGE=busybox

echo '{"image":"cgr.dev/'"${ORG}"'/'"${IMAGE}"'", "serviceAccountToken": "'"$(kubectl -n default create token --audience=https://issuer.enforce.dev default)"'", "serviceAccountAnnotations":{"credentials.chainguard.dev/identity":"'"$(kubectl get sa default -o 'jsonpath={.metadata.annotations.credentials\.chainguard\.dev/identity}')"'"}}' | go run .
```

If there are issues, you can check the `kubelet` logs for errors.

```
docker exec -it credential-provider-control-plane journalctl -u kubelet -f
```
