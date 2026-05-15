# Nexus APK Repository Setup for Chainguard Images

This guide walks through running Sonatype Nexus Repository Manager with a sidecar nginx proxy so that Nexus can serve Chainguard APK packages.
Chainguard virtual APK repos are found via your org and look something like https://apk.cgr.dev/$ORG_NAME/

This endpoint serves the APK index alongside packages you may require in your CI/CD pipelines if building complex images and components.

As of 15/04/2026(dd/mm/yyyy) SonarType Nexus does not support APK repositories. This solution provides customers using this platfrom a workaround to host APK repos and proxy requests using the `raw` repo type in Nexus. 

## Architecture

```
Nexus (port 8081)          ← Raw proxy repository pointing at nginx:8080
     │
     ▼
nginx auth proxy (port 8080)   ← injects Basic auth header
     │
     ▼
apk.cgr.dev/<your-org>         ← Chainguard APK registry
```

Nexus proxies through to the nginx sidecar, host or deployed proxy, which injects your Chainguard credentials before forwarding to `apk.cgr.dev`. End users only ever talk to Nexus — credentials stay server-side. You can handle your own auth or use anonymous access for these repos defined by your organisation. 

## Prerequisites
This is a demo setup, the same principals apply but you may want to consider more robust deployments if this is in production including:
* Nginx Sidecars for kubernetes ( proxy per nexus pod )
* A external proxy service running the nginx config ( ie cgr-nexus-proxy.$company.com )
* Corporate proxy solutions that support the name nginx config/process with your enterprise teams. 

The example below has been tested locally, and on a k8s deployment. This code example focuses on a quick example using Docker that you can run locally to prove out.

- Docker and Docker Compose v2
- A Chainguard account with APK access
- Your Chainguard **identity ID** and a valid **token** with the `apk.pull` role.

---

## Step 1 — Generate your auth credential

`CHAINGUARD_APK_AUTH` must be the **base64-encoded** form of `username:password` as output by `chainctl auth pull-token create`. The pull-token command prints the username and password as separate lines — you need to combine and encode them yourself.

Run the following, replacing `$ORGNAME` with your org (e.g. `domain.com`):

```bash
export ORGNAME=your-org.com

PULL_TOKEN=$(chainctl auth pull-token create --repository=apk --parent=$ORGNAME)

CG_USERNAME=$(echo "$PULL_TOKEN" | grep "^Username:" | awk '{print $2}')
CG_PASSWORD=$(echo "$PULL_TOKEN" | grep "^Password:" | awk '{print $2}')

export CHAINGUARD_APK_AUTH=$(echo -n "${CG_USERNAME}:${CG_PASSWORD}" | base64 | tr -d '\n')

echo "CHAINGUARD_APK_AUTH=$CHAINGUARD_APK_AUTH"
```

The username looks like `<identity-id>/<service-account-id>` and the password is a short-lived JWT. `tr -d '\n'` strips any line-wrap that `base64` adds on macOS — this matters, a newline in the middle of a Basic auth credential will silently break auth.

> **What not to do:** do not paste the raw `chainctl` output into the `.env`. The command prints human-readable instructions around the credential — only the base64 of `username:password` belongs in `CHAINGUARD_APK_AUTH`.

---

## Step 2 — Configure environment

Copy the example env file and fill in your values. Note this is just a local demo, leverage your secrets automation and corporate secrets for management of the token. This token authenticates to chainguard repos.

```bash
cp .env.example .env
```

Edit `.env` using the values from Step 1:

```env
CHAINGUARD_APK_ORG=your-org.com
CHAINGUARD_APK_AUTH=<output of the echo command above>
```



---

## Step 3 — Start the stack

```bash
docker compose up -d
```

Wait ~60 seconds for Nexus to finish initializing. You can tail the logs:

```bash
docker compose logs -f nexus
```

Nexus is ready when you see `Started Sonatype Nexus`.

---

## Step 4 — Retrieve the initial admin password

```bash
docker exec nexus cat /nexus-data/admin.password
```

---

## Step 5 — Log in and complete first-run setup

Open `http://localhost:8081` in your browser and sign in with:

- **Username:** `admin`
- **Password:** (from Step 4)

Follow the setup wizard. When prompted about anonymous access, choose based on your security requirements (disabling it is recommended for production).

---

## Step 6 — Create the APK proxy repository

Navigate to **Administration → Repository → Repositories → Create repository**.

Select **raw (proxy)** from the recipe list.

> **Warning:** Do not select `r (proxy)` — it appears nearby in the list and looks similar. Using the wrong recipe causes Nexus to try to parse APK archives as R packages, resulting in `IllegalStateException: No metadata file found` errors.

Fill in the repository settings:

### General

| Field | Value |
|-------|-------|
| Name  | `chainguard-apk` |
| Online | ✓ checked |


### Proxy
Note the name is the dns/friendly name in docker or your k8s environment. You can use pod IPs, localhost etc in k8s if using a sidecar pattern. 

Warning: You may need to allow SSRF protections in nexus to allow private addresses/endpoints. This can be done via the API:

```bash
curl -X PUT \
  -u admin:<nexus-admin-password> \
  -H "Content-Type: application/json" \
  "http://$NEXUS_URL/service/rest/v1/security/ssrf-protection" \
  -d '{
    "enabled": false
  }'
```

| Field | Value | Notes |
|-------|-------|-------|
| Remote Storage | `http://apk-auth-proxy:8080` | Pending how you deploy, this changes such as pod networking, svc, external networks etc.
| Maximum component age | 1 | ( you may tune this if you want to reduce network bandwidth, but remember we build packages frequently and the apkindex changes rapidly )
| Maximum metadata age   | 1 | ( this might not have any effect on raw types)

### Storage
You will need to disable Strict Content Type Validation as Nexus doesn't understand APK formats. This will prevent all packages outside the Index being served and working correctly.

### HTTP
Configure the following settings to support chainguard R2 redirects.

| Field | Value |
|-------|-------|
| Enable circular redirects | ✓ checked |

---

## Step 7 — Verify the proxy is working

Test that Nexus can reach the upstream through the proxy:

Create a Dockerfile and set the APK repo:
```
FROM cgr.dev/$ORGNAME/chainguard-base:latest

USER root

RUN echo "http://$NEXUS_URL/repository/chainguard-apk" \
      > /etc/apk/repositories

RUN apk update

RUN apk add curl
```

Build it with `docker build -f Dockerfile -t apk:test .`
Perform multiple builds to watch the nginx logs to verify pull through requests work and we're not using caches with `--no-cache` 

You can monitor both the nexus and nginx logs. You'll see traffic such as this:
```
192.168.97.3 - - [15/May/2026:02:13:15 +0000] "GET /aarch64/APKINDEX.tar.gz HTTP/1.1" 200 239684 "-" "Nexus/3.92.0-03 (COMMUNITY; Linux; 7.0.5-orbstack-00330-ge3df4e19b0a0-dirty; aarch64; 25.0.2)" "-"
192.168.97.3 - - [15/May/2026:02:13:15 +0000] "GET /aarch64/libbrotlicommon1-1.2.0-r3.apk HTTP/1.1" 304 0 "-" "Nexus/3.92.0-03 (COMMUNITY; Linux; 7.0.5-orbstack-00330-ge3df4e19b0a0-dirty; aarch64; 25.0.2)" "-"
192.168.97.3 - - [15/May/2026:02:13:16 +0000] "GET /aarch64/libbrotlidec1-1.2.0-r3.apk HTTP/1.1" 304 0 "-" "Nexus/3.92.0-03 (COMMUNITY; Linux; 7.0.5-orbstack-00330-ge3df4e19b0a0-dirty; aarch64; 25.0.2)" "-"
192.168.97.3 - - [15/May/2026:02:13:17 +0000] "GET /aarch64/krb5-conf-1.0-r9.apk HTTP/1.1" 304 0 "-" "Nexus/3.92.0-03 (COMMUNITY; Linux; 7.0.5-orbstack-00330-ge3df4e19b0a0-dirty; aarch64; 25.0.2)" "-"
192.168.97.3 - - [15/May/2026:02:13:18 +0000] "GET /aarch64/libcom_err-1.47.4-r1.apk HTTP/1.1" 304 0 "-" "Nexus/3.92.0-03 (COMMUNITY; Linux; 7.0.5-orbstack-00330-ge3df4e19b0a0-dirty; aarch64; 25.0.2)" "-"
192.168.97.3 - - [15/May/2026:02:13:18 +0000] "GET /aarch64/keyutils-libs-1.6.3-r38.apk HTTP/1.1" 304 0 "-" "Nexus/3.92.0-03 (COMMUNITY; Linux; 7.0.5-orbstack-00330-ge3df4e19b0a0-dirty; aarch64; 25.0.2)" "-"
192.168.97.3 - - [15/May/2026:02:13:19 +0000] "GET /aarch64/libverto-0.3.2-r7.apk HTTP/1.1" 304 0 "-" "Nexus/3.92.0-03 (COMMUNITY; Linux; 7.0.5-orbstack-00330-ge3df4e19b0a0-dirty; aarch64; 25.0.2)" "-"
192.168.97.3 - - [15/May/2026:02:13:20 +0000] "GET /aarch64/krb5-libs-1.22.2-r2.apk HTTP/1.1" 304 0 "-" "Nexus/3.92.0-03 (COMMUNITY; Linux; 7.0.5-orbstack-00330-ge3df4e19b0a0-dirty; aarch64; 25.0.2)" "-"
192.168.97.3 - - [15/May/2026:02:13:21 +0000] "GET /aarch64/gdbm-1.26-r5.apk HTTP/1.1" 304 0 "-" "Nexus/3.92.0-03 (COMMUNITY; Linux; 7.0.5-orbstack-00330-ge3df4e19b0a0-dirty; aarch64; 25.0.2)" "-"
192.168.97.3 - - [15/May/2026:02:13:22 +0000] "GET /aarch64/ncurses-terminfo-base-6.6.20260509-r0.apk HTTP/1.1" 304 0 "-" "Nexus/3.92.0-03 (COMMUNITY; Linux; 7.0.5-orbstack-00330-ge3df4e19b0a0-dirty; aarch64; 25.0.2)" "-"
192.168.97.3 - - [15/May/2026:02:13:22 +0000] "GET /aarch64/ncurses-6.6.20260509-r0.apk HTTP/1.1" 304 0 "-" "Nexus/3.92.0-03 (COMMUNITY; Linux; 7.0.5-orbstack-00330-ge3df4e19b0a0-dirty; aarch64; 25.0.2)" "-"
192.168.97.3 - - [15/May/2026:02:13:23 +0000] "GET /aarch64/readline-8.3-r2.apk HTTP/1.1" 304 0 "-" "Nexus/3.92.0-03 (COMMUNITY; Linux; 7.0.5-orbstack-00330-ge3df4e19b0a0-dirty; aarch64; 25.0.2)" "-"
192.168.97.3 - - [15/May/2026:02:13:24 +0000] "GET /aarch64/sqlite-libs-3.53.1-r0.apk HTTP/1.1" 304 0 "-" "Nexus/3.92.0-03 (COMMUNITY; Linux; 7.0.5-orbstack-00330-ge3df4e19b0a0-dirty; aarch64; 25.0.2)" "-"
192.168.97.3 - - [15/May/2026:02:13:25 +0000] "GET /aarch64/heimdal-libs-7.8.0-r48.apk HTTP/1.1" 304 0 "-" "Nexus/3.92.0-03 (COMMUNITY; Linux; 7.0.5-orbstack-00330-ge3df4e19b0a0-dirty; aarch64; 25.0.2)" "-"
192.168.97.3 - - [15/May/2026:02:13:25 +0000] "GET /aarch64/cyrus-sasl-heimdal-libs-2.1.28-r52.apk HTTP/1.1" 304 0 "-" "Nexus/3.92.0-03 (COMMUNITY; Linux; 7.0.5-orbstack-00330-ge3df4e19b0a0-dirty; aarch64; 25.0.2)" "-"
192.168.97.3 - - [15/May/2026:02:13:26 +0000] "GET /aarch64/libldap-2.6-2.6.13-r4.apk HTTP/1.1" 304 0 "-" "Nexus/3.92.0-03 (COMMUNITY; Linux; 7.0.5-orbstack-00330-ge3df4e19b0a0-dirty; aarch64; 25.0.2)" "-"
192.168.97.3 - - [15/May/2026:02:13:27 +0000] "GET /aarch64/libnghttp2-14-1.68.1-r2.apk HTTP/1.1" 304 0 "-" "Nexus/3.92.0-03 (COMMUNITY; Linux; 7.0.5-orbstack-00330-ge3df4e19b0a0-dirty; aarch64; 25.0.2)" "-"
192.168.97.3 - - [15/May/2026:02:13:28 +0000] "GET /aarch64/nghttp3-1.15.0-r1.apk HTTP/1.1" 304 0 "-" "Nexus/3.92.0-03 (COMMUNITY; Linux; 7.0.5-orbstack-00330-ge3df4e19b0a0-dirty; aarch64; 25.0.2)" "-"
192.168.97.3 - - [15/May/2026:02:13:28 +0000] "GET /aarch64/ngtcp2-1.22.1-r0.apk HTTP/1.1" 304 0 "-" "Nexus/3.92.0-03 (COMMUNITY; Linux; 7.0.5-orbstack-00330-ge3df4e19b0a0-dirty; aarch64; 25.0.2)" "-"
```
 