// HttpClientTest.java  (Java 11 target)
import javax.net.ssl.HttpsURLConnection;
import java.net.HttpURLConnection;
import java.net.URL;
import java.io.BufferedReader;
import java.io.InputStreamReader;

public class HttpClientTest {
    public static void main(String[] args) throws Exception {
        String target = args.length > 0 ? args[0] : "http://localhost:8080";
        System.out.println("Connecting to: " + target);

        URL url = new URL(target);
        String scheme = url.getProtocol();

        if ("https".equalsIgnoreCase(scheme)) {
            HttpsURLConnection conn = (HttpsURLConnection) url.openConnection();
            conn.setConnectTimeout(5000);
            conn.setReadTimeout(5000);
            conn.setRequestMethod("GET");
            int code = conn.getResponseCode();
            System.out.println("Response Code: " + code);
            try (BufferedReader br = new BufferedReader(new InputStreamReader(
                    (code >= 200 && code < 400) ? conn.getInputStream() : conn.getErrorStream()))) {
                String line; System.out.println("--- Response ---");
                while ((line = br.readLine()) != null) System.out.println(line);
                System.out.println("--- End ---");
            }
            conn.disconnect();
        } else if ("http".equalsIgnoreCase(scheme)) {
            HttpURLConnection conn = (HttpURLConnection) url.openConnection();
            conn.setConnectTimeout(5000);
            conn.setReadTimeout(5000);
            conn.setRequestMethod("GET");
            int code = conn.getResponseCode();
            System.out.println("Response Code: " + code);
            try (BufferedReader br = new BufferedReader(new InputStreamReader(
                    (code >= 200 && code < 400) ? conn.getInputStream() : conn.getErrorStream()))) {
                String line; System.out.println("--- Response ---");
                while ((line = br.readLine()) != null) System.out.println(line);
                System.out.println("--- End ---");
            }
            conn.disconnect();
        } else {
            throw new IllegalArgumentException("Unsupported scheme: " + scheme);
        }
    }
}

