#!/bin/sh
set -euo pipefail

ts() { date -u +'%Y-%m-%dT%H:%M:%SZ'; }

APP_ROOT="${APP_ROOT:-/app}"
CERT_DIR="${APP_ROOT}/certs"
TMP_DIR="${APP_ROOT}/tmp"

CA_PEM="${CERT_DIR}/ca.crt"
SERVER_CRT="${CERT_DIR}/server.crt"
SERVER_KEY="${CERT_DIR}/server.key"
CHAIN_PEM="${CERT_DIR}/chain.crt"   # optional

TRUSTSTORE_PATH="${CERT_DIR}/truststore.bcfks"
KEYSTORE_PATH="${CERT_DIR}/keystore.bcfks"
SERVER_PK8="${CERT_DIR}/server.pk8"

BC_DIR="/usr/share/java/bouncycastle-fips"
BC_JAR="${BC_DIR}/bc-fips.jar"

mkdir -p "${CERT_DIR}" "${TMP_DIR}"

# Providers/module-path only; no java.security append/override
export JDK_JAVA_OPTIONS="--module-path=${BC_DIR} --add-modules=jdk.crypto.ec,jdk.crypto.cryptoki ${JDK_JAVA_OPTIONS:-}"
export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:-}"

# Optional: enforce approved-only if set via env
if [ -n "${FIPS_APPROVED_ONLY:-}" ]; then
  export JAVA_OPTS="${JAVA_OPTS:-} -Dorg.bouncycastle.fips.approved_only=true"
fi

need_openssl() { command -v openssl >/dev/null 2>&1 || { echo "$(ts) ERROR: openssl not found"; exit 1; }; }
need_javac()   { command -v javac   >/dev/null 2>&1 || { echo "$(ts) ERROR: javac not found"; exit 1; }; }
need_java()    { command -v java    >/dev/null 2>&1 || { echo "$(ts) ERROR: java not found"; exit 1; }; }

# Strip inherited javax.net.ssl pins to avoid conflicts
_strip_ssl_flags() { sed -E 's/-Djavax\.net\.ssl\.(trust|key)Store(Type|Provider|Password)=[^ ]+//g'; }
[ -n "${JDK_JAVA_OPTIONS:-}" ]  && export JDK_JAVA_OPTIONS="$(printf '%s' "${JDK_JAVA_OPTIONS}"  | _strip_ssl_flags)"
[ -n "${JAVA_TOOL_OPTIONS:-}" ] && export JAVA_TOOL_OPTIONS="$(printf '%s' "${JAVA_TOOL_OPTIONS}" | _strip_ssl_flags)"
[ -n "${JAVA_OPTS:-}" ]         && export JAVA_OPTS="$(printf '%s' "${JAVA_OPTS}"         | _strip_ssl_flags)"

# --- Truststore plan ---
TRUSTSTORE_PASSWORD="${TRUSTSTORE_PASSWORD:-}"
if [ -f "${CA_PEM}" ] && { [ "${FORCE_REGEN:-0}" = "1" ] || [ ! -f "${TRUSTSTORE_PATH}" ]; }; then
  echo "$(ts) Creating BCFKS truststore (CA only) at ${TRUSTSTORE_PATH}"
  : "${TRUSTSTORE_PASSWORD:=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32 || true)}"
  export TRUSTSTORE_PASSWORD
  :> "${TMP_DIR}/.need_makebcfks"
elif [ ! -f "${CA_PEM}" ]; then
  echo "$(ts) WARN: ${CA_PEM} not found; no custom CA will be trusted."
fi

# --- Keystore plan ---
KEY_PASSWORD="${KEY_PASSWORD:-}"
if [ -f "${SERVER_CRT}" ] && [ -f "${SERVER_KEY}" ] && { [ "${FORCE_REGEN:-0}" = "1" ] || [ ! -f "${KEYSTORE_PATH}" ]; }; then
  echo "$(ts) Creating BCFKS keystore (server cert+key) at ${KEYSTORE_PATH}"
  : "${KEY_PASSWORD:=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32 || true)}"
  export KEY_PASSWORD
  need_openssl
  if ! grep -q "BEGIN PRIVATE KEY" "${SERVER_KEY}"; then
    openssl pkcs8 -topk8 -nocrypt -in "${SERVER_KEY}" -out "${SERVER_PK8}" ${PASSPHRASE:+-passin pass:"${PASSPHRASE}"} 2>/dev/null \
      || { echo "$(ts) ERROR: Failed to convert server.key to PKCS#8; check PASSPHRASE"; exit 1; }
  else
    cp -f "${SERVER_KEY}" "${SERVER_PK8}"
  fi
  :> "${TMP_DIR}/.need_makebcfks"
fi

# --- Write .bcfks if needed ---
if [ -f "${TMP_DIR}/.need_makebcfks" ]; then
  need_javac; need_java
  cat >"${TMP_DIR}/MakeBcfks.java" <<'***REMOVED***'
import java.io.InputStream; import java.io.OutputStream; import java.io.IOException;
import java.nio.file.*; import java.security.*; import java.security.cert.*; import java.security.spec.PKCS8EncodedKeySpec;
import java.util.*; public class MakeBcfks {
  static final String PROV_NAME="BCFIPS";
  static byte[] readAll(String p)throws IOException{return Files.readAllBytes(Paths.get(p));}
  static byte[] decodePem(byte[] in,String type){String s=new String(in);String b="-----BEGIN "+type+"-----",e="-----END "+type+"-----";
    int i=s.indexOf(b),j=s.indexOf(e); if(i>=0&&j>i){String b64=s.substring(i+b.length(),j).replaceAll("[\\r\\n\\s]","");return Base64.getDecoder().decode(b64);} return in;}
  static PrivateKey readPkcs8Key(String path)throws Exception{
    byte[] der=decodePem(readAll(path),"PRIVATE KEY"); PKCS8EncodedKeySpec spec=new PKCS8EncodedKeySpec(der);
    GeneralSecurityException last=null; for(String alg:new String[]{"RSA","EC","Ed25519","Ed448"}){
      try{return KeyFactory.getInstance(alg,PROV_NAME).generatePrivate(spec);}catch(GeneralSecurityException e){last=e;}}
    throw (last!=null)?last:new GeneralSecurityException("Unsupported key algorithm");}
  static KeyStore newBcfks(char[]pwd)throws Exception{KeyStore ks=KeyStore.getInstance("BCFKS",PROV_NAME); ks.load(null,pwd); return ks;}
  public static void main(String[] a)throws Exception{
    if(Security.getProvider(PROV_NAME)==null){
      Security.addProvider((Provider)Class.forName("org.bouncycastle.jcajce.provider.BouncyCastleFipsProvider").getDeclaredConstructor().newInstance());}
    String ca=System.getenv("CA_PEM"), leaf=System.getenv("SERVER_CRT"), chain=System.getenv("CHAIN_PEM"), pk8=System.getenv("SERVER_PK8"),
           ts=System.getenv("TRUSTSTORE_PATH"), ks=System.getenv("KEYSTORE_PATH");
    char[] tsp=Optional.ofNullable(System.getenv("TRUSTSTORE_PASSWORD")).orElse("").toCharArray();
    char[] ksp=Optional.ofNullable(System.getenv("KEY_PASSWORD")).orElse("").toCharArray();
    if(ca!=null && Files.isRegularFile(Paths.get(ca)) && !Files.isRegularFile(Paths.get(ts))){
      KeyStore T=newBcfks(tsp); CertificateFactory cf=CertificateFactory.getInstance("X.509");
      try(InputStream is=Files.newInputStream(Paths.get(ca))){int i=0; for(java.security.cert.Certificate c: cf.generateCertificates(is)){T.setCertificateEntry("ca-"+(i++),c);}}
      try(OutputStream os=Files.newOutputStream(Paths.get(ts))){T.store(os,tsp);} System.out.println("Wrote truststore: "+ts);
    }
    if(leaf!=null && Files.isRegularFile(Paths.get(leaf)) && pk8!=null && Files.isRegularFile(Paths.get(pk8)) && !Files.isRegularFile(Paths.get(ks))){
      PrivateKey key=readPkcs8Key(pk8); List<java.security.cert.Certificate> list=new ArrayList<>(); CertificateFactory cf=CertificateFactory.getInstance("X.509");
      try(InputStream is=Files.newInputStream(Paths.get(leaf))){list.addAll((Collection<? extends java.security.cert.Certificate>)cf.generateCertificates(is));}
      if(chain!=null && Files.isRegularFile(Paths.get(chain))){try(InputStream cs=Files.newInputStream(Paths.get(chain))){list.addAll((Collection<? extends java.security.cert.Certificate>)cf.generateCertificates(cs));}}
      KeyStore K=newBcfks(ksp); K.setKeyEntry("app-server",key,ksp,list.toArray(new java.security.cert.Certificate[0]));
      try(OutputStream os=Files.newOutputStream(Paths.get(ks))){K.store(os,ksp);} System.out.println("Wrote keystore: "+ks);
    }
  }
}
***REMOVED***
  javac -cp "${BC_JAR}" "${TMP_DIR}/MakeBcfks.java"
  CA_PEM="${CA_PEM}" SERVER_CRT="${SERVER_CRT}" CHAIN_PEM="${CHAIN_PEM}" \
  SERVER_PK8="${SERVER_PK8}" TRUSTSTORE_PATH="${TRUSTSTORE_PATH}" KEYSTORE_PATH="${KEYSTORE_PATH}" \
  TRUSTSTORE_PASSWORD="${TRUSTSTORE_PASSWORD:-}" KEY_PASSWORD="${KEY_PASSWORD:-}" \
  java -cp "${TMP_DIR}:${BC_JAR}" MakeBcfks
  rm -f "${TMP_DIR}/.need_makebcfks" "${SERVER_PK8}" || true
fi

# Pin BCFKS stores at runtime (only if they exist + passwords set)
RUNTIME_PROPS=""
[ -f "${TRUSTSTORE_PATH}" ] && [ -n "${TRUSTSTORE_PASSWORD:-}" ] && RUNTIME_PROPS="${RUNTIME_PROPS} -Djavax.net.ssl.trustStore=${TRUSTSTORE_PATH} -Djavax.net.ssl.trustStoreType=BCFKS -Djavax.net.ssl.trustStoreProvider=BCFIPS -Djavax.net.ssl.trustStorePassword=${TRUSTSTORE_PASSWORD}"
[ -f "${KEYSTORE_PATH}" ] && [ -n "${KEY_PASSWORD:-}" ] && RUNTIME_PROPS="${RUNTIME_PROPS} -Djavax.net.ssl.keyStore=${KEYSTORE_PATH} -Djavax.net.ssl.keyStoreType=BCFKS -Djavax.net.ssl.keyStoreProvider=BCFIPS -Djavax.net.ssl.keyStorePassword=${KEY_PASSWORD}"

echo "$(ts) JAVA_TOOL_OPTIONS=${JAVA_TOOL_OPTIONS}"
[ -n "${TRUSTSTORE_PASSWORD:-}" ] && echo "$(ts) truststore: ${TRUSTSTORE_PATH} (pwd len: ${#TRUSTSTORE_PASSWORD})"
[ -n "${KEY_PASSWORD:-}" ] && echo   "$(ts) keystore:   ${KEYSTORE_PATH} (pwd len: ${#KEY_PASSWORD})"

APP_JAR="${APP_JAR:-${APP_ROOT}/lib/app.jar}"
if [ -f "$APP_JAR" ]; then
  echo "$(ts) Launching Java app: ${APP_JAR}"
  exec java ${JAVA_OPTS:-} ${RUNTIME_PROPS} -jar "${APP_JAR}"
else
  echo "[WARN] No ${APP_JAR}; sleeping for debug"
  exec sleep 600
fi