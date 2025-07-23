import javax.net.ssl.*;

public class BadCipherTest {
    public static void main(String[] args) throws Exception {
        SSLContext sslContext = SSLContext.getInstance("TLS");
        sslContext.init(null, null, null);
        
        SSLSocket socket = (SSLSocket) sslContext.getSocketFactory().createSocket("chainguard.dev", 443);
        
        String cipher = args.length > 0 ? args[0] : "TLS_CHACHA20_POLY1305_SHA256";
        socket.setEnabledCipherSuites(new String[]{cipher});
        
        try {
            socket.startHandshake();
            System.out.println("Connection successful - TLS: " + socket.getSession().getProtocol() + ", Cipher: " + socket.getSession().getCipherSuite());
        } catch (Exception e) {
            throw e;
        }
        socket.close();
    }
}

