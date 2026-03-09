import java.security.Provider;
import java.security.Security;
import java.util.Set;
import java.util.TreeSet;

import org.bouncycastle.jce.provider.BouncyCastleProvider;
import org.bouncycastle.pqc.jcajce.provider.BouncyCastlePQCProvider;

/**
 * Lists all PQC algorithms available from Bouncy Castle by querying
 * the JCA Security registry after registering both BC providers.
 *
 * Based on BouncyCastlePQCProvider source:
 * https://github.com/bcgit/bc-java/tree/main/prov/src/main/java/org/bouncycastle/pqc
 *
 */
public class PQCTest {

    public static void main(String[] args) {
        Security.addProvider(new BouncyCastlePQCProvider());

        Provider bcpqc = Security.getProvider("BCPQC");

        System.out.println("=================================================");
        System.out.println("  BCPQC Provider Algorithm Listing");
        System.out.println("=================================================");
        System.out.printf("  Provider : %s%n", bcpqc.getInfo());
        System.out.printf("  Version  : %.2f%n", bcpqc.getVersion());
        System.out.println("-------------------------------------------------");

        String[] serviceTypes = { "KeyPairGenerator", "KeyGenerator", "Signature", "KeyFactory", "Cipher", "KeyAgreement" };

        Set<String> pqcPrefixes = Set.of(
            "ML-KEM", "MLKEM", "ML-DSA", "MLDSA", "SLH-DSA", "SLHDSA"
        );

        for (String serviceType : serviceTypes) {
            Set<String> algs = new TreeSet<>();
            for (Provider.Service service : bcpqc.getServices()) {
                if (!service.getType().equalsIgnoreCase(serviceType)) continue;
                String algUpper = service.getAlgorithm().toUpperCase();
                for (String prefix : pqcPrefixes) {
                    if (algUpper.startsWith(prefix)) {
                        algs.add(service.getAlgorithm());
                        break;
                    }
                }
            }
            if (!algs.isEmpty()) {
                System.out.printf("%n  [%s]%n", serviceType);
                algs.forEach(alg -> System.out.printf("    %s%n", alg));
            }
        }

        System.out.println("\n=================================================");
    }
}