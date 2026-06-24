# Renovate Datasource

A [Renovate custom datasource](https://docs.renovatebot.com/modules/datasource/custom/)
for Chainguard images.

It implements two features:

1. A configurable cooldown that only updates to tags and digests that
   are at least *N* days in the past.
2. Changelog URLs, via a custom UI that diffs the old and the new images.

## Build

```
go build ./cmd/renovate-cooldown-datasource
```

Or, build the container image:

```
docker build -t renovate-cooldown-datasource:dev .
```

## Run

### Locally

Run the service locally and reuse the local credentials provided by `chainctl`:

```
# Login to Chainguard
chainctl auth login

# Run the service
./renovate-cooldown-datasource --org=my.org.com
```

### Kubernetes

See [`k8s/manifests.yaml`](k8s/manifests.yaml) for an example of deploying the
service to a Kubernetes cluster.

Create an assumable identity as described in [the
documentation](https://edu.chainguard.dev/chainguard/administration/assumable-ids/identity-examples/kubernetes-identity/)
with the `registry.pull` role. For a cluster whose OIDC issuer is reachable
from the internet:

```
chainctl iam identity create renovate-cooldown-datasource \
  --parent=<your-chainguard-org> \
  --identity-issuer=<your-cluster-oidc-issuer-url> \
  --subject=system:serviceaccount:default:renovate-cooldown-datasource \
  --role=registry.pull
```

Note the printed identity UIDP — that's the value for `CHANGE_ME_IDENTITY`
below. The `--subject` matches the ServiceAccount in `k8s/manifests.yaml`;
adjust the namespace if you deploy elsewhere.

For air-gapped clusters whose issuer URL isn't reachable, swap `--identity-issuer`
for `--issuer-keys="$(kubectl get --raw /openid/v1/jwks)"` per the
[docs](https://edu.chainguard.dev/chainguard/administration/assumable-ids/identity-examples/kubernetes-identity/).

Then edit the three `CHANGE_ME_*` placeholders in `k8s/manifests.yaml`:
- `CHANGE_ME_IMAGE` (the service docker image)
- `CHANGE_ME_ORG` (your organization id)
- `CHANGE_ME_IDENTITY` (the assumable identity UIDP)

```
kubectl apply -f k8s/manifests.yaml
```

## Configuring Renovate

Point Renovate's `customDatasources` at the service, use a `customManagers`
regex to extract `cgr.dev/{org}/*` `FROM` lines, and disable other managers so
the built-in Dockerfile manager doesn't race the custom one and resolve digests
directly against cgr.dev (which would defeat the cooldown).

```jsonc
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "enabledManagers": ["custom.regex"],
  "customDatasources": {
    "chainguard-cooldown": {
      "defaultRegistryUrlTemplate": "http://renovate-cooldown-datasource/v1/releases/{{packageName}}",
      "format": "json"
    }
  },
  "customManagers": [
    {
      "customType": "regex",
      "fileMatch": ["(^|/)Dockerfile$"],
      "matchStrings": [
        "FROM\\s+cgr\\.dev/my-org/(?<packageName>[A-Za-z0-9._/-]+):(?<currentValue>[A-Za-z0-9._-]+)(@(?<currentDigest>sha256:[a-f0-9]+))?"
      ],
      "datasourceTemplate": "custom.chainguard-cooldown",
    }
  ],
  "packageRules": [
    {
      "matchDatasources": ["custom.chainguard-cooldown"],
      "changelogUrl": "http://renovate-cooldown-datasource/repo/{{packageName}}/diff/{{#if currentDigest}}{{currentDigest}}{{else}}{{currentValue}}{{/if}}/{{#if newDigest}}{{newDigest}}{{else}}{{newValue}}{{/if}}"
    }
  ]
}
```

Note, `enabledManagers: ["custom.regex"]` is heavy-handed. Itt disables every
other manager in your config (npm, helm, etc.). If you have other managers you
want to keep enabled, replace it with a more surgical disable: 

```json
{
  "dockerfile": {
    "enabled": false
  }
}
```

Or, a packageRule that disables the `dockerfile` manager only for
`cgr.dev/my-org/*` packages.

## How It Works

### Cooldown

For each tag in a Chainguard repo:

- If the tag's current digest is older than the cooldown window → return the tag, the update time, and the digest as-is.
- If the current digest is newer than the cooldown window → walk the tag's history and return the most recent digest that *was* old enough.
- If no historical digest satisfies the cooldown → omit the tag.

A `GET /v1/releases/{repo}` response looks like:

```json
{
  "releases": [
    {
      "version": "3.14.5",
      "releaseTimestamp": "2026-06-10T20:18:06.42Z",
      "digest": "sha256:163cc24b066e0ea18daa4966227cdb8e61c2cf9f49681bc566459506901533a6"
    },
    {
      "version": "3.14.6",
      "releaseTimestamp": "2026-06-14T18:46:31.317Z",
      "digest": "sha256:d5312494fbc793de620941d10e2bc04f0c2ce67706b9da2071b297474218c719"
    }
  ]
}
```

### Changelogs

Visiting `<datasource-url>/repo/node/diff/{{currentDigest}}/{{newDigest}}` will
show a changelog that compares the differences between the two images.

It does this by fetching the image config and SBOMs for each image and comparing
the contents.
