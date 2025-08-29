# Filebeat Journald

An example of running the Chainguard `filebeat` image with the `journald` input.

## Requirements

- Access to Chainguard's `filebeat` image in your organization.
- These tools:
  - `chainctl`
  - `crane`
  - `docker`
  - `envsubst`
  - `kind`
  - `kubectl`

## Usage

Export your organization ID for use in subsequent commands:

```
export ORGANIZATION=your.org
```

Apply the custom overlay to your `filebeat` image. This adds the `systemd`
package.

```
chainctl image repo build apply \
    --parent=$ORGANIZATION \
    --repo=filebeat \
    -f custom_overlay.yaml \
    --yes
```

This will kick off a build. Wait for it to complete. Run this command to check
the status of the builds.

```
watch chainctl image repo build list --parent=$ORGANIZATION --repo=filebeat
```

Spin up a `kind` cluster.

```
./kind.sh
```

Apply the manifests.

```
kubectl apply -f - < <(envsubst < manifests.yaml)
```

Observe systemd logs in the filebeat output.

```
kubectl logs daemonset/filebeat -n filebeat -f
```
