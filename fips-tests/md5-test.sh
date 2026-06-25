#!/bin/sh
docker run --rm -it --entrypoint sh bcfks-app -lc '
set -e

# 1) Make a temporary FIPS-only java.security overlay (NO SUN crypto provider)
cat >/tmp/java-fips-only.properties <<***REMOVED***
security.provider.1=org.bouncycastle.jcajce.provider.BouncyCastleFipsProvider C:HYBRID;ENABLE{ALL};
security.provider.2=org.bouncycastle.jsse.provider.BouncyCastleJsseProvider fips:BCFIPS
security.provider.3=org.bouncycastle.entropy.provider.BouncyCastleEntropyProvider
# Keep non-crypto helpers (no SUN crypto):
security.provider.4=SunJGSS
security.provider.5=SunSASL
security.provider.6=XMLDSig
security.provider.7=SunPCSC
security.provider.8=JdkLDAP
security.provider.9=JdkSASL

org.bouncycastle.fips.approved_only=true
keystore.type=bcfks
keystore.type.compat=true
***REMOVED***

# 2) Compile a quick test (no CLASSPATH inheritance)
cat >/tmp/Bad.java << "SRC"
import javax.crypto.Cipher;
import java.security.MessageDigest;
public class Bad {
  public static void main(String[] a) throws Exception {
    try { MessageDigest.getInstance("MD5"); System.out.println("UNEXPECTED: MD5 allowed"); }
    catch (Exception e) { System.out.println("OK: MD5 blocked -> " + e.getClass().getSimpleName()); }
    try { Cipher.getInstance("DES/CBC/PKCS5Padding"); System.out.println("UNEXPECTED: DES allowed"); }
    catch (Exception e) { System.out.println("OK: DES blocked -> " + e.getClass().getSimpleName()); }
  }
}
SRC
javac -cp "" /tmp/Bad.java

# 3) Run with the FIPS-only overlay in effect
JAVA_TOOL_OPTIONS="-Dsecurity.overridePropertiesFile=true -Djava.security.properties=/tmp/java-fips-only.properties" \
  java -cp /tmp Bad
'