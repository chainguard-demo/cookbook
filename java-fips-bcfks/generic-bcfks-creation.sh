#!/bin/sh
set -euo pipefail

ts() { date -u +'%Y-%m-%dT%H:%M:%SZ'; }
log() { echo "$(ts) $*"; }

# =============================================================================
# Config (override via env)
# =============================================================================
OUT_DIR="${OUT_DIR:-/app/ssl}"
TMP_DIR="${TMP_DIR:-/tmp/fips-ssl}"

TRUSTSTORE="${TRUSTSTORE:-${OUT_DIR}/truststore.bcfks}"
KEYSTORE="${KEYSTORE:-${OUT_DIR}/keystore.bcfks}"

TRUSTSTORE_PASSWORD="${TRUSTSTORE_PASSWORD:-changeit}"
KEYSTORE_PASSWORD="${KEYSTORE_PASSWORD:-changeit}"

BC_DIR="${BC_DIR:-/usr/share/java/bouncycastle-fips}"
BC_JAR="${BC_JAR:-${BC_DIR}/bc-fips.jar}"

ENFORCE_APPROVED_ONLY="${ENFORCE_APPROVED_ONLY:-1}"

# Local identity (only needed if you want a server cert)
SERVER_ALIAS="${SERVER_ALIAS:-server}"
SERVER_DNAME="${SERVER_DNAME:-CN=localhost}"
SERVER_SAN="${SERVER_SAN:-dns:localhost,ip:127.0.0.1}"

KEYALG="${KEYALG:-RSA}"
KEYSIZE="${KEYSIZE:-2048}"
VALIDITY_DAYS="${VALIDITY_DAYS:-825}"

# =============================================================================
# Validate environment
# =============================================================================
command -v keytool >/dev/null || { log "ERROR: keytool not found"; exit 1; }
[ -f "${BC_JAR}" ] || { log "ERROR: bc-fips.jar not found"; exit 1; }

mkdir -p "${OUT_DIR}" "${TMP_DIR}"

# =============================================================================
# Locate JDK cacerts
# =============================================================================
find_cacerts() {
  for p in \
    "${JAVA_HOME:-}/lib/security/cacerts" \
    /usr/lib/jvm/default-jvm/lib/security/cacerts \
    /usr/lib/jvm/java-*/lib/security/cacerts \
    /etc/ssl/certs/java/cacerts; do
    [ -f "$p" ] && echo "$p" && return 0
  done
  return 1
}

CACERTS="$(find_cacerts || true)"
[ -n "${CACERTS}" ] || { log "ERROR: JDK cacerts not found"; exit 1; }
log "Using JDK cacerts: ${CACERTS}"

# =============================================================================
# keytool wrapper (BC-FIPS)
# =============================================================================
run_keytool() {
  env -u JAVA_TOOL_OPTIONS -u JDK_JAVA_OPTIONS \
    JAVA_TOOL_OPTIONS="--module-path=${BC_DIR} --add-modules=jdk.crypto.ec,jdk.crypto.cryptoki" \
    keytool \
      -providername BCFIPS \
      -providerclass org.bouncycastle.jcajce.provider.BouncyCastleFipsProvider \
      -providerpath "${BC_JAR}" \
      "$@"
}

# =============================================================================
# 1️⃣ Create empty BCFKS truststore
# =============================================================================
if [ ! -f "${TRUSTSTORE}" ]; then
  log "Creating empty BCFKS truststore"
  run_keytool -genkeypair \
    -alias __bootstrap__ \
    -dname "CN=bootstrap" \
    -keyalg RSA -keysize 2048 \
    -keystore "${TRUSTSTORE}" \
    -storetype BCFKS \
    -storepass "${TRUSTSTORE_PASSWORD}" \
    -keypass "${TRUSTSTORE_PASSWORD}" \
    -validity 1
  run_keytool -delete \
    -alias __bootstrap__ \
    -keystore "${TRUSTSTORE}" \
    -storetype BCFKS \
    -storepass "${TRUSTSTORE_PASSWORD}"
fi

# =============================================================================
# 2️⃣ Import ALL public CA certs from JDK cacerts
# =============================================================================
log "Importing JDK public CA certificates into BCFKS truststore"

keytool -list -cacerts -storepass changeit \
| awk -F, '/trustedCertEntry/ {print $1}' \
| while read -r alias; do
    [ -n "$alias" ] || continue
    CRT="${TMP_DIR}/${alias}.crt"
    if keytool -exportcert -rfc \
        -cacerts \
        -storepass changeit \
        -alias "$alias" \
        -file "$CRT" 2>/dev/null; then
      run_keytool -importcert -noprompt \
        -alias "jdk-${alias}" \
        -file "$CRT" \
        -keystore "${TRUSTSTORE}" \
        -storetype BCFKS \
        -storepass "${TRUSTSTORE_PASSWORD}" \
        >/dev/null 2>&1 || true
    fi
  done

# =============================================================================
# 3️⃣ Create BCFKS keystore (server identity)
# =============================================================================
if [ ! -f "${KEYSTORE}" ]; then
  log "Creating BCFKS keystore"
  run_keytool -genkeypair \
    -alias "${SERVER_ALIAS}" \
    -dname "${SERVER_DNAME}" \
    -ext "SAN=${SERVER_SAN}" \
    -keyalg "${KEYALG}" \
    -keysize "${KEYSIZE}" \
    -validity "${VALIDITY_DAYS}" \
    -keystore "${KEYSTORE}" \
    -storetype BCFKS \
    -storepass "${KEYSTORE_PASSWORD}" \
    -keypass "${KEYSTORE_PASSWORD}"
fi

# =============================================================================
# 4️⃣ Sanity checks
# =============================================================================
run_keytool -list \
  -keystore "${TRUSTSTORE}" \
  -storetype BCFKS \
  -storepass "${TRUSTSTORE_PASSWORD}" >/dev/null

run_keytool -list \
  -keystore "${KEYSTORE}" \
  -storetype BCFKS \
  -storepass "${KEYSTORE_PASSWORD}" >/dev/null

log "BCFKS truststore and keystore ready"

# =============================================================================
# 5️⃣ Optional output: JVM flags for runtime
# =============================================================================
echo
echo "Recommended JVM flags:"
echo "--module-path=${BC_DIR} --add-modules=jdk.crypto.ec,jdk.crypto.cryptoki \\"
[ "${ENFORCE_APPROVED_ONLY}" = "1" ] && \
  echo "-Dorg.bouncycastle.fips.approved_only=true \\"
cat <<***REMOVED***
-Djavax.net.ssl.trustStore=${TRUSTSTORE}
-Djavax.net.ssl.trustStoreType=BCFKS
-Djavax.net.ssl.trustStoreProvider=BCFIPS
-Djavax.net.ssl.trustStorePassword=${TRUSTSTORE_PASSWORD}
-Djavax.net.ssl.keyStore=${KEYSTORE}
-Djavax.net.ssl.keyStoreType=BCFKS
-Djavax.net.ssl.keyStoreProvider=BCFIPS
-Djavax.net.ssl.keyStorePassword=${KEYSTORE_PASSWORD}
***REMOVED***
