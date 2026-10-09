# chainctl config validate — standalone scripts

Two scripts that check whether a machine can actually reach every endpoint Chainguard tooling needs. They cover the same endpoints as `chainctl config validate` and print in chainctl's table and JSON layout, but they don't need chainctl installed.

| File | Runs on |
|---|---|
| `chainctl-config-validate.sh` | macOS (bash 3.2+), Linux, WSL, Git Bash. Needs `curl`. |
| `chainctl-config-validate.ps1` | Windows PowerShell 5.1 and PowerShell 7+ (Windows, macOS, Linux). |

## Usage

```bash
./chainctl-config-validate.sh              # table (default)
./chainctl-config-validate.sh -o wide      # table plus a TEST column (what was checked, what came back)
./chainctl-config-validate.sh -o json      # JSON
./chainctl-config-validate.sh -v           # also print the raw error for each failure (stderr)
```

```powershell
.\chainctl-config-validate.ps1
.\chainctl-config-validate.ps1 -o wide
.\chainctl-config-validate.ps1 -o json
.\chainctl-config-validate.ps1 -Verbose
.\chainctl-config-validate.ps1 -Help
# If execution policy blocks it:
powershell -ExecutionPolicy Bypass -File .\chainctl-config-validate.ps1
```

The only options are `-o`/`--output` (`table`, `wide` or `json`), `--timeout` (seconds per request, 10 by default), `-v`/`--verbose` and `-h`/`--help`. In PowerShell they are `-o`, `-Timeout`, `-Verbose` and `-Help`.

## Why not just DNS?

`chainctl config validate` only does a DNS lookup for most hosts. That isn't a connectivity test:

- **False pass:** corporate networks often resolve external names but block or proxy outbound port 443. DNS succeeds while the connection doesn't.
- **False fail:** behind an explicit proxy, the workstation often can't resolve external names at all, yet tools that use the proxy connect fine.

So every check here is a real HTTPS request. It uses the same proxy settings as other tools: `HTTPS_PROXY` / `NO_PROXY` for curl, and the system or environment proxy for .NET.

## What it checks

| Rows | Check | Passes when |
|---|---|---|
| `platform.api`, `platform.console`, `platform.issuer`, `platform.registry` | HTTPS GET of the URL | The server sent back any HTTP response. |
| `domains.*` (8 required third-party domains) | HTTPS GET `https://<domain>/` | The server sent back any HTTP response. |
| `protocol.grpc.platform.{api,issuer}` | gRPC `PingService/Ping` over HTTP/2 | An HTTP/2 response came back with `grpc-status: 0`. |
| `protocol.http.platform.{api,issuer}` | HTTP GET `/ping/v1/ping` | 2xx **and** the body is the ping JSON. |
| `issuer/.well-known/openid-configuration`, `issuer/keys` | HTTP GET | 2xx **and** the body is the expected OIDC JSON. |

Results:

- ✅ means it's reachable.
- ❗ means the request got an answer, but the status was **403, 407, 451 or 511**. Proxies and firewalls typically use these for block pages, so it may not be the real server.
- ❌ means it's not reachable, and the cell gives the reason:
  - `Cannot resolve <host> (DNS)`
  - `Cannot connect to <host>:443`
  - `Timed out after Ns`
  - `Blocked by proxy (HTTP 403)`
  - `Connection reset (firewall?)`
  - `TLS certificate not trusted (TLS-inspecting proxy?)`
  - `HTTP 200 but not the expected response (proxy page?)`

The protocol checks always run, even if a host looked unreachable. chainctl's "skip if DNS failed" shortcut is gone.

`-o wide` adds a TEST column. It shows what was checked and, for rows that passed or were flagged, what came back, for example `HTTPS GET / (HTTP 400, cert issuer: WE1)`. **The certificate issuer is the quickest way to spot TLS inspection:** if unrelated sites (GitHub, Google, Cloudflare) all show the same issuer, such as a Zscaler or corporate CA, a proxy is decrypting the traffic.

JSON entries have `Value`, `Result` (`pass` / `warn` / `fail`), `Detail` and `Test`.

Example (abridged), from a network where a proxy blocks one domain and TLS inspection breaks another:

```
                  NAME                   |              VALUE              |                         RESULT
-----------------------------------------|---------------------------------|--------------------------------------------------------
                  domains.github-content |       raw.githubusercontent.com |                         ❌ Blocked by proxy (HTTP 403)
                    domains.package-repo |              packages.wolfi.dev |                                                     ✅
 issuer/.well-known/openid-configuration |      https://issuer.enforce.dev |                                           HTTP enabled
                            platform.api | https://console-api.enforce.dev |                                                     ✅
                       platform.registry |                 https://cgr.dev | ❌ TLS certificate not trusted (TLS-inspecting proxy?)
              protocol.grpc.platform.api | https://console-api.enforce.dev |                                           gRPC enabled
              protocol.http.platform.api | https://console-api.enforce.dev |                                           HTTP enabled
```

## Where the platform URLs come from

Same as `chainctl config validate` run with no flags: **`CHAINGUARD_PLATFORM_*` env vars > config file > production defaults**. The config file is the one set in `CHAINCTL_CONFIG`, otherwise the first one found in this order:

- `./chainctl/config.yaml`
- `<user config dir>/chainctl/config.yaml`
- `~/.chainguard/config.yaml`

An invalid URL falls back to the default and prints a `Configuration error:` warning.

The exit code is `0` when the checks ran, even if some failed, matching chainctl. A non-zero exit means the script itself couldn't run.

## Limitations

- **Domains that answer with a normal-looking page:** a TLS-inspecting proxy that returns its block page with HTTP 200 can't be told apart from the real site on the `domains.*` and `platform.*` rows. The API and issuer rows check the response body, so they do catch this. On the other rows, look at the cert issuer in `-o wide`.
- **`googlecode.l.googleusercontent.com`:** this is a CNAME target, and a browser on an open network couldn't load it over HTTPS. The script treats a TLS rejection from the real server as reachable. Check how it's classified on a network you know is unrestricted.
- **Windows PowerShell 5.1 can't do HTTP/2.** It falls back to `curl.exe` if that build supports HTTP/2. Otherwise the gRPC rows say `gRPC check unavailable` and a warning is printed. Use `pwsh` (PowerShell 7+) for the full check.
- The scripts don't print chainctl's warning about unknown keys in the config file.
