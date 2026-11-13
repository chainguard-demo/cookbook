# Pull token rotation

[`rotate-pull-token.yaml`](../.github/workflows/rotate-pull-token.yaml) is a reusable workflow that keeps a Chainguard pull token fresh for tools that can't assume a Chainguard identity, such as Dependabot. Each run:

1. Creates a pull token with `chainctl auth pull-token create`.
2. Stores its username and password as repository secrets, Dependabot secrets by default.
3. Deletes the older pull tokens with the same name, once the secrets hold the new one.

Call it on a schedule shorter than the token's TTL, so a token is always replaced before it expires:

```yaml
name: Rotate the Dependabot JavaScript pull token
on:
  schedule:
    - cron: '0 6 * * 1'
  workflow_dispatch:
permissions: {}
jobs:
  rotate:
    permissions:
      id-token: write
    uses: chainguard-demo/cookbook/.github/workflows/rotate-pull-token.yaml@<commit-sha>
    with:
      identity: <identity-uidp>
      parent: <organization>
      name: dependabot-javascript
      repositories: javascript
      ttl: 720h
      username-secret: CHAINGUARD_JAVASCRIPT_PULL_TOKEN_USERNAME
      password-secret: CHAINGUARD_JAVASCRIPT_PULL_TOKEN_PASSWORD
    secrets:
      github-token: ${{ secrets.SECRETS_WRITER_TOKEN }}
```

## Inputs

| Input | Required | Default | Description |
| --- | --- | --- | --- |
| `identity` | yes | | Chainguard identity the workflow assumes. |
| `parent` | yes | | Organization or folder for `--parent`. |
| `name` | yes | | Pull token name for `--name`; older tokens with this name are deleted. Letters, digits, `.`, `_` and `-`. |
| `repositories` | no | `oci` | Comma-separated repository types for `--repository`, such as `javascript` or `go,python`. |
| `ttl` | no | `720h` | Token lifetime for `--ttl`; the maximum depends on the organization's plan. |
| `description` | no | names the calling run | Token description for `--description`. |
| `username-secret` | yes | | Secret for the token's username. |
| `password-secret` | yes | | Secret for the token's password. |
| `secret-repository` | no | calling repository | Repository to set the secrets on, as `owner/name`. |
| `secret-app` | no | `dependabot` | `dependabot`, `actions` or `codespaces`. |
| `delete-older` | no | `true` | Delete older tokens with the same name. |

The `github-token` secret must be able to write that kind of secret on `secret-repository`, such as a fine-grained token or GitHub App installation token with the Dependabot secrets (or Secrets) permission. `GITHUB_TOKEN` can't write secrets.

## The Chainguard identity

The identity needs to create pull tokens for each repository type, through the matching `*.pull_token_creator` role, and `identity.list` and `identity.delete` to remove older tokens. Only `owner` has both among the built-in roles; a custom role can combine the pull token creator capabilities with the two identity ones instead.

The OIDC token comes from the calling workflow, so the identity should match the caller's repository, for example the subject `repo:<owner>/<repo>:ref:refs/heads/main` for scheduled runs. Its `job_workflow_ref` claim names this workflow, if you want to pin the identity to it.
