# Generic Registries

## crane

[crane](https://github.com/google/go-containerregistry/blob/main/cmd/crane/README.md)
is a tool that allows you to interact with OCI repositories.

See
[recipes.md](https://github.com/google/go-containerregistry/blob/main/cmd/crane/recipes.md)
for additional recipes.

### Getting images using the Catalog API

```sh
crane catalog <registry>
```

This command will query a registry for available repositories using the
[OCI Catalog API](https://github.com/opencontainers/distribution-spec/blob/main/extensions/README.md).
NOTE: not all registries support this endpoint.

Registries we know this works with:

- Google Container Registry
- Google Artifact Registry
- Harbor
- Microsoft Container Registry

#### Examples

- `crane catalog gcr.io`

### Listing tags

```sh
crane ls <repo> --omit-digest-tags --full-ref
```

- `--omit-digest-tags` suppresses `.sbom`/`.att` tags.
- `--full-ref` prints the full image reference.
