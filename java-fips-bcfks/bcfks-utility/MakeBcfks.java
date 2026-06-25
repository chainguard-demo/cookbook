#!/bin/sh
set -euo pipefail

ts() { date -u +'%Y-%m-%dT%H:%M:%SZ'; }

# ---------- Inputs & paths ----------
CERT_DIR="/ninja/certs"
CA_PEM="${CERT_DIR}/ca.crt"
SERVER_CRT="${CERT_DIR}/server.crt"
SERVER_KEY="${CERT_DIR}/server.key"
CHAIN_PEM="${CERT_DIR}/chain.crt"   # optional

TRUSTSTORE_PATH="${CERT_DIR}/truststore.bcfks"
KEYSTORE_PATH="${CERT_DIR}/keystore.bcfks"

# temp for pkcs8
SERVER_PK8="${CERT_DIR}/server.pk8"

BC_DIR="/usr/share/java/bouncycastle-fips"     # bc-fips.jar lives here on Chainguard
BC_JAR="${BC_DIR}/bc-fips.jar"
APPEND_FILE="/etc/java-crypto.append"

mkdir -p "${CERT_DIR}" /ninja/tmp

need_openssl() { command -v openssl >/dev/null 2>&1 || { echo "$(ts) ERROR: openssl not found"; exit 1; }; }
need_javac()   { command -v javac   >/dev/null 2>&1 || { echo "$(ts) ERROR: javac not found"; exit 1; }; }
need_java()    { command -v java    >/dev/null 2>&1 || { echo "$(ts) ERROR: java not found"; exit 1; }; }

# ---------- JVM / Providers ----------
# Expose BC-FIPS modules
export JDK_JAVA_OPTIONS="--module-path=${BC_DIR} --add-modules=jdk.crypto.ec,jdk.crypto.cryptoki ${JDK_JAVA_OPTIONS:-}"
export JAVA_TOOL_OPTIONS="--module-path=${BC_DIR} ${JAVA_TOOL_OPTIONS:-}"

# (Optional) append SunJCE; harmless, but not needed for BCFKS
if [ ! -s "${APPEND_FILE}" ]; then
  cat >"${APPEND_FILE}" <<'***REMOVED***'
keystore.type.compat=true
security.provider.20=com.sun.crypto.provider.SunJCE
***REMOVED***
fi
export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS} -Dsecurity.overridePropertiesFile=false -Djava.security.properties=${APPEND_FILE}"

# Optional: enforce BC FIPS approved-only for runtime TLS
if [ -n "${FIPS_APPROVED_ONLY:-}" ]; then
  export JAVA_OPTS="${JAVA_OPTS:-} -Dorg.bouncycastle.fips.approved_only=true"
fi

# ---------- Strip inherited javax.net.ssl pins (avoid conflicts) ----------
_strip_ssl_flags() { sed -E 's/-Djavax\.net\.ssl\.(trust|key)Store(Type|Provider|Password)=[^ ]+//g'; }
[ -n "${JDK_JAVA_OPTIONS:-}" ]  && export JDK_JAVA_OPTIONS="$(printf '%s' "${JDK_JAVA_OPTIONS}"  | _strip_ssl_flags)"
[ -n "${JAVA_TOOL_OPTIONS:-}" ] && export JAVA_TOOL_OPTIONS="$(printf '%s' "${JAVA_TOOL_OPTIONS}" | _strip_ssl_flags)"
[ -n "${JAVA_OPTS:-}" ]         && export JAVA_OPTS="$(printf '%s' "${JAVA_OPTS}"         | _strip_ssl_flags)"

# ---------- 1) Plan BCFKS truststore ----------
TRUSTSTORE_PASSWORD="${TRUSTSTORE_PASSWORD:-}"
if [ -f "${CA_PEM}" ] && [ ! -f "${TRUSTSTORE_PATH}" ]; then
  echo "$(ts) Creating BCFKS truststore (CA only) at ${TRUSTSTORE_PATH}"
  TRUSTSTORE_PASSWORD="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32 || true)"
  export TRUSTSTORE_PASSWORD
  :> /ninja/tmp/.need_makebcfks
elif [ ! -f "${CA_PEM}" ]; then
  echo "$(ts) WARN: ${CA_PEM} not found; no custom CA will be trusted."
fi

# ---------- 2) Plan BCFKS keystore (server cert+key) ----------
KEY_PASSWORD="${KEY_PASSWORD:-}"
if [ -f "${SERVER_CRT}" ] && [ -f "${SERVER_KEY}" ] && [ ! -f "${KEYSTORE_PATH}" ]; then
  KEY_PASSWORD="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32 || true)"
  export KEY_PASSWORD
  echo "$(ts) Creating BCFKS keystore (server cert+key) at ${KEYSTORE_PATH}"
  need_openssl
  # Convert any format to unencrypted PKCS#8 (no prompt: use PASSPHRASE if encrypted)
  openssl pkcs8 -topk8 -nocrypt \
    -in "${SERVER_KEY}" \
    -out "${SERVER_PK8}" \
    ${PASSPHRASE:+-passin pass:"${PASSPHRASE}"} 2>/dev/null || {
      echo "$(ts) ERROR: Failed to convert server.key to PKCS#8; check PASSPHRASE"; exit 1; }
  :> /ninja/tmp/.need_makebcfks
elif [ ! -f "${SERVER_CRT}" ] || [ ! -f "${SERVER_KEY}" ]; then
  echo "$(ts) INFO: No ${SERVER_CRT} or ${SERVER_KEY}; skipping keystore creation."
fi

# ---------- 3) Compile & run helper to write .bcfks stores ----------
if [ -f /ninja/tmp/.need_makebcfks ]; then
  need_javac; need_java
  [ -f "${BC_JAR}" ] || { echo "$(ts) ERROR: ${BC_JAR} not found"; exit 1; }

  cat >/ninja/tmp/MakeBcfks.java <<'***REMOVED***'
import java.io.*;
import java.nio.file.*;
import java.security.*;
import java.security.cert.*;
import java.security.spec.PKCS8EncodedKeySpec;
import java.util.*;

public class MakeBcfks {
  static final String PROV_NAME = "BCFIPS";

  static byte[] readAll(String p) throws IOException { return Files.readAllBytes(Paths.get(p)); }

  static byte[] decodePem(byte[] in, String type) {
    String s = new String(in);
    String begin = "-----BEGIN " + type + "-----";
    String end   = "-----END " + type + "-----";
    int i = s.indexOf(begin), j = s.indexOf(end);
    if (i >= 0 && j > i) {
      String b64 = s.substring(i + begin.length(), j).replaceAll("[\\r\\n\\s]", "");
      return Base64.getDecoder().decode(b64);
    }
    return in; // assume DER if not PEM-wrapped
  }

  static PrivateKey readPkcs8Key(String path) throws Exception {
    byte[] der = decodePem(readAll(path), "PRIVATE KEY");
    PKCS8EncodedKeySpec spec = new PKCS8EncodedKeySpec(der);
    String[] algs = { "RSA", "EC", "Ed25519", "Ed448" };
    GeneralSecurityException last = null;
    for (String alg : algs) {
      try { return KeyFactory.getInstance(alg, PROV_NAME).generatePrivate(spec); }
      catch (GeneralSecurityException e) { last = e; }
    }
    throw (last != null) ? last : new GeneralSecurityException("Unsupported key algorithm");
  }

  static KeyStore newBcfks(char[] pwd) throws Exception {
    KeyStore ks = KeyStore.getInstance("BCFKS", PROV_NAME);
    ks.load(null, pwd);
    return ks;
  }

  public static void main(String[] args) throws Exception {
    if (Security.getProvider(PROV_NAME) == null) {
      Security.addProvider(
        (Provider)Class.forName("org.bouncycastle.jcajce.provider.BouncyCastleFipsProvider")
                       .getDeclaredConstructor().newInstance()
      );
    }

    String caPem     = System.getenv("CA_PEM");
    String leafCrt   = System.getenv("SERVER_CRT");
    String chainPem  = System.getenv("CHAIN_PEM");
    String pk8Path   = System.getenv("SERVER_PK8");
    String tsPath    = System.getenv("TRUSTSTORE_PATH");
    String ksPath    = System.getenv("KEYSTORE_PATH");
    char[] tsPass    = Optional.ofNullable(System.getenv("TRUSTSTORE_PASSWORD")).orElse("").toCharArray();
    char[] ksPass    = Optional.ofNullable(System.getenv("KEY_PASSWORD")).orElse("").toCharArray();

    CertificateFactory cf = CertificateFactory.getInstance("X.509", PROV_NAME);

    if (caPem != null && Files.isRegularFile(Paths.get(caPem)) && !Files.isRegularFile(Paths.get(tsPath))) {
      KeyStore ts = newBcfks(tsPass);
      try (InputStream is = Files.newInputStream(Paths.get(caPem))) {
        int idx = 0;
        for (Certificate c : cf.generateCertificates(is)) {
          ts.setCertificateEntry("ca-" + (idx++), c);
        }
      }
      try (OutputStream os = Files.newOutputStream(Paths.get(tsPath))) { ts.store(os, tsPass); }
      System.out.println("Wrote truststore: " + tsPath);
    }

    if (leafCrt != null && Files.isRegularFile(Paths.get(leafCrt)) &&
        pk8Path != null && Files.isRegularFile(Paths.get(pk8Path)) &&
        !Files.isRegularFile(Paths.get(ksPath))) {

      PrivateKey key = readPkcs8Key(pk8Path);

      List<Certificate> chain = new ArrayList<>();
      try (InputStream is = Files.newInputStream(Paths.get(leafCrt))) {
        chain.addAll((Collection<? extends Certificate>)cf.generateCertificates(is));
      }
      if (chainPem != null && Files.isRegularFile(Paths.get(chainPem))) {
        try (InputStream cs = Files.newInputStream(Paths.get(chainPem))) {
          chain.addAll((Collection<? extends Certificate>)cf.generateCertificates(cs));
        }
      }

      KeyStore ks = newBcfks(ksPass);
      ks.setKeyEntry("ninja-server", key, ksPass, chain.toArray(new Certificate[0]));
      try (OutputStream os = Files.newOutputStream(Paths.get(ksPath))) { ks.store(os, ksPass); }
      System.out.println("Wrote keystore: " + ksPath);
    }
  }
}
***REMOVED***

  echo "$(ts) Compiling MakeBcfks.java"
  javac -cp "${BC_JAR}" /ninja/tmp/MakeBcfks.java

  echo "$(ts) Generating BCFKS stores"
  CA_PEM="${CA_PEM}" SERVER_CRT="${SERVER_CRT}" CHAIN_PEM="${CHAIN_PEM}" \
  SERVER_PK8="${SERVER_PK8}" TRUSTSTORE_PATH="${TRUSTSTORE_PATH}" KEYSTORE_PATH="${KEYSTORE_PATH}" \
  TRUSTSTORE_PASSWORD="${TRUSTSTORE_PASSWORD:-}" KEY_PASSWORD="${KEY_PASSWORD:-}" \
  java -cp "/ninja/tmp:${BC_JAR}" MakeBcfks

  rm -f /ninja/tmp/.need_makebcfks "${SERVER_PK8}" || true
fi

# ---------- 4) Force BCFKS at runtime ----------
RUNTIME_PROPS=""
if [ -f "${TRUSTSTORE_PATH}" ] && [ -n "${TRUSTSTORE_PASSWORD:-}" ]; then
  RUNTIME_PROPS="${RUNTIME_PROPS} \
   -Djavax.net.ssl.trustStore=${TRUSTSTORE_PATH} \
   -Djavax.net.ssl.trustStoreType=BCFKS \
   -Djavax.net.ssl.trustStoreProvider=BCFIPS \
   -Djavax.net.ssl.trustStorePassword=${TRUSTSTORE_PASSWORD}"
fi
if [ -f "${KEYSTORE_PATH}" ] && [ -n "${KEY_PASSWORD:-}" ]; then
  RUNTIME_PROPS="${RUNTIME_PROPS} \
   -Djavax.net.ssl.keyStore=${KEYSTORE_PATH} \
   -Djavax.net.ssl.keyStoreType=BCFKS \
   -Djavax.net.ssl.keyStoreProvider=BCFIPS \
   -Djavax.net.ssl.keyStorePassword=${KEY_PASSWORD}"
fi

echo "$(ts) JAVA_TOOL_OPTIONS=${JAVA_TOOL_OPTIONS}"
[ -n "${TRUSTSTORE_PASSWORD:-}" ] && echo "$(ts) truststore: ${TRUSTSTORE_PATH} (pwd len: ${#TRUSTSTORE_PASSWORD})"
[ -n "${KEY_PASSWORD:-}" ] && echo   "$(ts) keystore:   ${KEYSTORE_PATH} (pwd len: ${#KEY_PASSWORD})"

# ---------- 5) Launch the app ----------
APP_JAR="${APP_JAR:-/ninja/lib/app.jar}"
if [ -f "$APP_JAR" ]; then
  echo "$(ts) Launching Java app: ${APP_JAR}"
  exec java ${JAVA_OPTS:-} ${RUNTIME_PROPS} -jar "${APP_JAR}"
else
  echo "[WARN] No ${APP_JAR}; sleeping for debug"
  exec sleep 600
fi {
    
}
