# Identify FIPS support in Apache Pinot

## Goals

Identify Java code that potentially violates FIPS cryptography standards by using Apache Pinot as an example. The analysis is not comprhensive or authoritative but more to flag easily identifiable code to review

When the code base is updated to use BouncyCastle for cryptography then regressions will also be helpful to identify areas of non-compliance. In other words, when Bouncy Castle is loaded as a security provider, any breakage will be helpful to identify other areas of non-compliance

## Detailed list of checks

This script checks for the following:
- Custom Cryptography Implementations: Detects classes implementing cryptographic interfaces (`Cipher`, `MessageDigest`, `KeyGenerator`, `SecureRandom`, `Mac`, `Signature`, `CipherSpi`, `MessageDigestSpi`). Custom implementations are rarely FIPS-validated.
- MD5 Algorithm Usage: Identifies all MD5 usage patterns: `MD5`, `"MD5"`, `MessageDigest.getInstance("MD5")`, `DigestUtils.md5`, `Algorithm.MD5`.  
- SHA1 (checks the same locations as MD5)
- Keystores that are not compliance such as PKCS12. These keystores may need to be converted to BCFKS
- TLS/SSL Implementation: Scans for TLS/SSL API usage (SSLContext, SSLEngine, etc) and validates that is using BCJSSE (The BouncyCastle implementation of JSSE). Standard JDK TLS providers (SunJSSE) does not provide FIPS validated cryptopgraphy.
- Insecure Random Number Generation: Flags `new java.util.Random(` usage that's not `SecureRandom`. 
- Key Generation and Manipulation: Identifies common key operations (for example generateKey) that will need to be manually checked
- Importing alternative crytography implementations: Scans for imports of: `javax.crypto`, `java.security`, `javax.net.ssl`, `java.security.cert`. Findings will need to be audited to ensure FIPS-compliance
- Weak Cipher Suites: Detects deprecated ciphers (DES, RC2, SSLv2, etc)
- Certificate Validation: Audit that certificate validation to ensure that the configuration does not disable validation checks
- BouncyCastle FIPS Provider: Verifies presence of: `BCFIPS`, `org.bouncycastle.*fips`, `bc-fips`.  
- BouncyCastle FIPS is the recommended FIPS 140-2/140-3 validated provider for Java.
- java.security configuration: Analyzes `java.security` files to verify BCFIPS provider is configured, detect non-FIPS providers, priority order, etc
- java.security Property String: Scans code for runtime security property manipulation: `System.setProperty("java.security"...)`, `System.getProperty("java.security"...)`.  
- Security Provider Registration: Detects: `Security.addProvider`, `Security.insertProviderAt`, custom provider installation.  

## Basic Usage

```bash
./fips-compliance-check.sh
```

Note: To include test files, change `SKIP_TEST_DIRS=false`.

## Example Output

```
FIPS Compliance Check - Apache Pinot
====================================

Checking: Custom cryptography implementations
Checking: MD5 algorithm usage
./pinot-common/src/main/java/org/apache/pinot/common/function/scalar/HashFunctions.java
./pinot-plugins/pinot-file-system/pinot-adls/src/main/java/org/apache/pinot/plugin/filesystem/ADLSGen2PinotFS.java
./pinot-plugins/pinot-file-system/pinot-s3/src/main/java/org/apache/pinot/plugin/filesystem/S3Config.java
./pinot-plugins/pinot-input-format/pinot-avro/src/main/java/org/apache/pinot/plugin/inputformat/avro/KafkaAvroMessageDecoder.java
./pinot-segment-local/src/main/java/org/apache/pinot/segment/local/utils/HashUtils.java
./pinot-spi/src/main/java/org/apache/pinot/spi/config/table/HashFunction.java

Checking: SHA1 algorithm usage
Checking: PKCS12 keystores
./pinot-common/src/main/java/org/apache/pinot/common/utils/ClientSSLContextGenerator.java
./pinot-common/src/main/java/org/apache/pinot/common/utils/fetcher/HttpsSegmentFetcher.java
./pinot-plugins/pinot-stream-ingestion/pinot-kafka-base/src/main/java/org/apache/pinot/plugin/stream/kafka/KafkaSSLUtils.java

Checking: TLS/SSL usage without BCJSSE
./pinot-broker/src/main/java/org/apache/pinot/broker/grpc/BrokerGrpcServer.java
./pinot-clients/pinot-java-client/src/main/java/org/apache/pinot/client/BrokerCache.java
./pinot-clients/pinot-java-client/src/main/java/org/apache/pinot/client/JsonAsyncHttpPinotClientTransport.java
./pinot-clients/pinot-java-client/src/main/java/org/apache/pinot/client/JsonAsyncHttpPinotClientTransportFactory.java
./pinot-clients/pinot-java-client/src/main/java/org/apache/pinot/client/utils/ConnectionUtils.java
...

Checking: Insecure random number generation
Checking: Key generation and manipulation
./pinot-broker/src/main/java/org/apache/pinot/broker/grpc/BrokerGrpcServer.java
./pinot-common/src/main/java/org/apache/pinot/common/config/TlsConfig.java
./pinot-common/src/main/java/org/apache/pinot/common/utils/ClientSSLContextGenerator.java
...

Checking: Cryptographic package imports
./pinot-clients/pinot-java-client/src/main/java/org/apache/pinot/client/BrokerCache.java
./pinot-clients/pinot-java-client/src/main/java/org/apache/pinot/client/JsonAsyncHttpPinotClientTransport.java
...

Checking: FIPS-related keywords
Checking: Weak cipher suites
Checking: Certificate validation and handling
Checking: BouncyCastle FIPS provider usage
Checking: java.security configuration files
Checking: java.security property configuration
Checking: Security provider registration
====================================
Scan complete
```

The output shows which checks found violations. Each check prints its name and lists the files that may violate FIPS compliance for that particular check. If no files are found for a check, only the check name is printed without any file list.

## References

- [FIPS 140-3 Standard](https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.140-3.pdf)
- [BouncyCastle FIPS](https://www.bouncycastle.org/fips-java/)
- [BouncyCastle JSSE](https://www.bouncycastle.org/jsse-provider)
- [Apache Pinot Documentation](https://pinot.apache.org/)
