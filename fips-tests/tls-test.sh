#!/bin/sh
docker run --rm -it \
  -e KEY_PASSWORD=changeme \
  -e TRUSTSTORE_PASSWORD=changeme \
  -e FORCE_REGEN=1 \
  --entrypoint sh bcfks-app -lc '
set -eu

# If the BCFKS stores don’t exist yet, let your run.sh create them
if [ ! -s /app/certs/truststore.bcfks ] || [ ! -s /app/certs/keystore.bcfks ]; then
  echo "[INFO] Creating BCFKS stores via /app/bin/run.sh ..."
  APP_JAR=/does/not/exist /app/bin/run.sh >/tmp/init.log 2>&1 &
  INIT_PID=$!
  for i in $(seq 1 20); do
    [ -s /app/certs/truststore.bcfks ] && [ -s /app/certs/keystore.bcfks ] && break
    sleep 0.5
  done
  kill "$INIT_PID" 2>/dev/null || true
  echo "[INFO] Stores ready."
fi

# FIPS-only security overlay (BCFIPS providers only)
cat >/tmp/java-fips-only.properties <<***REMOVED***
security.provider.1=org.bouncycastle.jcajce.provider.BouncyCastleFipsProvider C:HYBRID;ENABLE{ALL};
security.provider.2=org.bouncycastle.jsse.provider.BouncyCastleJsseProvider fips:BCFIPS
security.provider.3=org.bouncycastle.entropy.provider.BouncyCastleEntropyProvider
org.bouncycastle.fips.approved_only=true
keystore.type=bcfks
keystore.type.compat=true
***REMOVED***

# Minimal TLS echo server/client that prints providers + cipher
cat >/tmp/TlsServer.java << "SRC"
import javax.net.ssl.*; import java.io.*;
public class TlsServer {
  public static void main(String[] a) throws Exception {
    SSLServerSocketFactory sf = (SSLServerSocketFactory) SSLServerSocketFactory.getDefault();
    SSLServerSocket ss = (SSLServerSocket) sf.createServerSocket(8443);
    System.out.println("SERVER provider=" + sf.getClass().getName());
    System.out.println("SERVER enabled=" + String.join(",", ss.getEnabledCipherSuites()));
    SSLSocket s = (SSLSocket) ss.accept();
    new PrintWriter(new OutputStreamWriter(s.getOutputStream()), true).println("hello-from-server");
    System.out.println("SERVER sent, cipher=" + s.getSession().getCipherSuite());
    s.close(); ss.close();
  }
}
SRC

cat >/tmp/TlsClient.java << "SRC"
import javax.net.ssl.*; import java.io.*; import java.net.Socket;
public class TlsClient {
  public static void main(String[] a) throws Exception {
    SSLSocketFactory cf = (SSLSocketFactory) SSLSocketFactory.getDefault();
    System.out.println("CLIENT provider=" + cf.getClass().getName());
    SSLSocket s = (SSLSocket) cf.createSocket("127.0.0.1", 8443);
    s.startHandshake();
    BufferedReader br = new BufferedReader(new InputStreamReader(s.getInputStream()));
    System.out.println("CLIENT recv=" + br.readLine());
    System.out.println("CLIENT cipher=" + s.getSession().getCipherSuite());
    s.close();
  }
}
SRC

# Compile with a clean classpath
cd /tmp
javac -cp "" TlsServer.java TlsClient.java

# Start TLS server using BCFKS keystore
JAVA_TOOL_OPTIONS="-Dsecurity.overridePropertiesFile=true -Djava.security.properties=/tmp/java-fips-only.properties" \
java -cp /tmp \
 -Djavax.net.ssl.keyStore=/app/certs/keystore.bcfks \
 -Djavax.net.ssl.keyStoreType=BCFKS \
 -Djavax.net.ssl.keyStoreProvider=BCFIPS \
 -Djavax.net.ssl.keyStorePassword=${KEY_PASSWORD} \
 TlsServer &

sleep 1

# Run TLS client using BCFKS truststore
JAVA_TOOL_OPTIONS="-Dsecurity.overridePropertiesFile=true -Djava.security.properties=/tmp/java-fips-only.properties" \
java -cp /tmp \
 -Djavax.net.ssl.trustStore=/app/certs/truststore.bcfks \
 -Djavax.net.ssl.trustStoreType=BCFKS \
 -Djavax.net.ssl.trustStoreProvider=BCFIPS \
 -Djavax.net.ssl.trustStorePassword=${TRUSTSTORE_PASSWORD} \
 TlsClient
'