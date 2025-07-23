import javax.net.ssl.*;
import java.io.FileInputStream;
import java.security.KeyStore;

public class BadCipherTest {
    public static void main(String[] args) throws Exception {
        // Load keystore (for client certs, optional if you don't need mutual TLS)
        KeyStore keyStore = KeyStore.getInstance("PKCS12");
        keyStore.load(new FileInputStream("client-keystore.p12"), "changeit".toCharArray());

        // Load truststore (to verify server certs)
        KeyStore trustStore = KeyStore.getInstance("PKCS12");
        trustStore.load(new FileInputStream("truststore.p12"), "changeit".toCharArray());

        // Set up KeyManager and TrustManager
        KeyManagerFactory kmf = KeyManagerFactory.getInstance("SunX509");
        kmf.init(keyStore, "changeit".toCharArray());

        TrustManagerFactory tmf = TrustManagerFactory.getInstance("SunX509");
        tmf.init(trustStore);

        // Initialize SSL context
        SSLContext sslContext = SSLContext.getInstance("TLS");
        sslContext.init(kmf.getKeyManagers(), tmf.getTrustManagers(), null);

        // Create socket and set cipher
        SSLSocket socket = (SSLSocket) sslContext.getSocketFactory().createSocket("chainguard.dev", 443);

        String cipher = args.length > 0 ? args[0] : "TLS_CHACHA20_POLY1305_SHA256";
        socket.setEnabledCipherSuites(new String[]{cipher});

        try {
            socket.startHandshake();
            System.out.println("Connection successful - TLS: " + socket.getSession().getProtocol() +
                               ", Cipher: " + socket.getSession().getCipherSuite());
        } catch (Exception e) {
            System.err.println("Handshake failed: " + e.getMessage());
            throw e;
        } finally {
            socket.close();
        }
    }
}

