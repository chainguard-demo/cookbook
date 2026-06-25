# BCFKS & FIPS Verification

This project demonstrates a fully self-contained Java 11 runtime using Chainguard’s FIPS-validated Corretto JDK,
configured with BouncyCastle FIPS providers and BCFKS keystore/truststore formats. It provides:

**Automatic FIPS-Compliant Keystore Generation**

On startup, the container automatically constructs Java BCFKS truststores and keystores using the BouncyCastle FIPS provider.
It reads your provided ca.crt, server.crt, and server.key files, generating fully valid FIPS-compatible stores — no manual keytool commands required.

**Secure Configuration**
If no TRUSTSTORE_PASSWORD or KEY_PASSWORD is provided, the initialization script dynamically generates strong, random 32-character credentials.
A temporary server.pk8 (PKCS #8) key file is created during build time and securely removed once the BCFKS keystore is finalized.

**FIPS-Mode Runtime Enforcement**

The Java runtime is launched with BCFIPS as the primary cryptographic provider. All truststore and keystore paths are injected as system properties at startup, ensuring that TLS and crypto operations use only FIPS-approved algorithms throughout container execution.

---

## Requirements & Overview

Make sure your app distribution tarball (`dist.tar.gz`) exists in the root of this directory (root app directory)

```
tar -czf dist.tar.gz -C app .
```

It must contain:

```
app/
├─ bin/
│   └─ run.sh          # main entrypoint
├─ lib/
│   └─ app.jar         # your Java app (e.g., HttpClientTest)
├─ certs/
│   ├─ ca.crt
│   ├─ server.crt
│   └─ server.key
```

To test TLS and store creation, ensure the following files exist under app/certs/:

* ca.crt - Root CA certificate used to populate the truststore
* server.crt - Leaf certificate presented by the TLS server
* server.key -Corresponding private key 

**NOTE: You are responsible for generating your own certs and keys for testing. These are not include**

When run.sh starts, it automatically builds both stores:

* app/certs/truststore.bcfks
* app/certs/keystore.bcfks

### How it works (run.sh)

1. Generates random passwords (or uses KEY_PASSWORD / TRUSTSTORE_PASSWORD if provided).
2. Creates .bcfks keystore and truststore if they don’t exist or FORCE_REGEN=1.
3. Uses embedded Java helper (MakeBcfks.java) to:
    - Convert server.key to PKCS#8.
    - Import server.crt + chain into a BCFKS keystore.
    - Import ca.crt into a BCFKS truststore.
4. Pins both stores at runtime with the BCFIPS provider
5. Enforces FIPS-approved mode via -Dorg.bouncycastle.fips.approved_only=true

##  Build Image

```
docker build -t bcfks-app .
```

## Tests

### Providers Test

Lists all active security providers in your FIPS runtime and verifies loaded stores:

Expected output:
```
[INFO] Listing generated BCFKS stores...
Keystore type: BCFKS
Keystore provider: BCFIPS

Your keystore contains 1 entry

ca-0, Oct 29, 2025, trustedCertEntry,
Certificate fingerprint (SHA-256): <redacted>

Keystore type: BCFKS
Keystore provider: BCFIPS

Your keystore contains 1 entry

app-server, Oct 29, 2025, PrivateKeyEntry,
Certificate fingerprint (SHA-256): <redacted>
...........
127.0.0.1 - - [29/Oct/2025 20:48:12] "GET / HTTP/1.1" 200 -
2025-10-29T20:48:11Z Creating BCFKS truststore (CA only) at /app/certs/truststore.bcfks
2025-10-29T20:48:11Z Creating BCFKS keystore (server cert+key) at /app/certs/keystore.bcfks
```

### MD5 Test

Verifies that MD5 and DES are blocked when FIPS_APPROVED_ONLY=1 is active.

Expected output:
```
OK: MD5 blocked -> java.security.NoSuchAlgorithmException: MD5 not available
OK: DES blocked -> java.security.NoSuchAlgorithmException: DES not available
``` 

### TLS Test

Runs a BCFIPS-only TLS handshake using the generated BCFKS stores.

Expected output:
```
SERVER provider=org.bouncycastle.jsse.provider.ProvSSLContextSpi
SERVER cipher=TLS_AES_256_GCM_SHA384
CLIENT cipher=TLS_AES_256_GCM_SHA384
CLIENT recv=hello-from-server
```

