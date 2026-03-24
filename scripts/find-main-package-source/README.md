# find-main-package-source

Traces a Chainguard container image back to the upstream source of its main
package.

## Requirements

The following tools must be available on `PATH`:

| Tool | Purpose |
|------|---------|
| [`crane`](https://github.com/google/go-containerregistry/blob/main/cmd/crane/README.md) | Resolve image digest and read image config |
| [`cosign`](https://github.com/sigstore/cosign) | Download image attestations |
| [`chainctl`](https://edu.chainguard.dev/chainguard/administration/how-to-install-chainctl/) | Authenticate against private APK repositories |
| `curl` | Fetch APK files |
| [`yq`](https://github.com/mikefarah/yq) | Parse the melange YAML embedded in the APK |
| `jq` | Parse JSON from crane and cosign output |
| `tar` | Extract `.melange.yaml` from the APK archive |

You must also be authenticated with `chainctl` (`chainctl auth login`) if the
image belongs to a private organization.

## Usage

```
./find-main-package-source.sh cgr.dev/<ORG>/<IMAGE_NAME>:<TAG>
```

The image reference must follow the `cgr.dev/{ORG}/{IMAGE_NAME}:{TAG}` format.

## Example

```console
$ ./find-main-package-source.sh cgr.dev/your.org/dotnet-runtime:10
Image:        cgr.dev/your.org/dotnet-runtime@sha256:f2b6dc97ea9a30a733e3889764eafde4dd4eafe6715edc154305d69d717f322e
Main package: dotnet-10
Version:      10.0.105-r0
APK:          https://apk.cgr.dev/chainguard/x86_64/dotnet-10-10.0.105-r0.apk
Source:       https://github.com/dotnet/dotnet
Tag:          v10.0.105
Commit:       a612c2a1056fe3265387ae3ff7c94eba1505caf9
```
