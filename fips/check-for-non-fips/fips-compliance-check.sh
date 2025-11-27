#!/bin/bash

# FIPS Compliance Check Script for Apache Pinot
# Identifies Java code that potentially violates FIPS cryptography standards

# Configuration
REPO_URL="https://github.com/apache/pinot.git"
REPO_DIR="pinot"
SKIP_TEST_DIRS=true

# Cryptographic-related packages that require review
CRYPTO_PACKAGES="javax\.crypto|java\.security|javax\.net\.ssl|java\.security\.cert"

# FIPS-related keywords for deeper analysis
FIPS_KEYWORDS="FIPS|Cipher|KeyGen|Symmetric|Asymmetric|Secret|KeyStore|Digest|PKCS|Encod|Decod|Algorithm|Password|Random|Entropy|Signature|Certificate"

# Function to filter out test files
filter_test_files() {
    if [ "$SKIP_TEST_DIRS" = true ]; then
        grep -v -E "(test/|tests/|src/test/|src/itest/|/Test[^/]*\.java|/.*Test\.java|/.*Tests\.java)" || true
    else
        cat
    fi
}

# Function to search for patterns in Java files only
search_java_files() {
    local pattern="$1"
    grep -r --include="*.java" -E "$pattern" . 2>/dev/null | \
        grep -v "\.git/" | cut -d: -f1 | sort -u | filter_test_files
}

# Clone or update repository
if [ -d "$REPO_DIR" ]; then
    cd "$REPO_DIR"
    git fetch origin 2>/dev/null || true
    git checkout main 2>/dev/null || true
    cd ..
else
    git clone "$REPO_URL" "$REPO_DIR" 2>/dev/null || true
fi

if [ ! -d "$REPO_DIR" ]; then
    echo "Error: Failed to clone or access repository at $REPO_DIR" >&2
fi

cd "$REPO_DIR" || exit 1

echo "FIPS Compliance Check - Apache Pinot"
echo "===================================="
echo ""

# Check 1: Custom cryptography implementations
echo "Checking: Custom cryptography implementations"
crypto_impl_files=$(grep -r --include="*.java" \
    -E "implements\s+(Cipher|MessageDigest|KeyGenerator|SecureRandom|Mac|Signature|CipherSpi|MessageDigestSpi)" . 2>/dev/null | \
    grep -v "\.git/" | cut -d: -f1 | sort -u | filter_test_files)

if [ -n "$crypto_impl_files" ]; then
    echo "$crypto_impl_files"
    echo ""
fi

# Check 2: MD5 usage
echo "Checking: MD5 algorithm usage"
md5_files=$(search_java_files '(MD5|md5|"MD5"|MessageDigest\.getInstance\s*\(\s*"MD5"|DigestUtils\.md5|Algorithm\.MD5)')
if [ -n "$md5_files" ]; then
    echo "$md5_files"
    echo ""
fi

# Check 3: SHA1 usage
echo "Checking: SHA1 algorithm usage"
sha1_files=$(search_java_files '("SHA1"|"SHA-1"|"SHA_1"|MessageDigest\.getInstance\s*\(\s*"SHA1"|Algorithm\.SHA1)')
if [ -n "$sha1_files" ]; then
    echo "$sha1_files"
    echo ""
fi

# Check 4: Non-compliant keystores (PKCS12 only, no PKCS11)
echo "Checking: PKCS12 keystores"
pkcs12_files=$(search_java_files '(PKCS12|pkcs12|"PKCS12"|KeyStore\.getInstance\s*\(\s*"PKCS12")')
if [ -n "$pkcs12_files" ]; then
    echo "$pkcs12_files"
    echo ""
fi

# Check 5: TLS/SSL usage without BCJSSE
echo "Checking: TLS/SSL usage without BCJSSE"
tls_usage=$(grep -r --include="*.java" \
    -E "(SSLContext|SSLSocketFactory|SSLEngine|TrustManager|KeyManager|SSLSocket|HttpsURLConnection)" . 2>/dev/null | \
    grep -v "\.git/" | cut -d: -f1 | sort -u | filter_test_files)

if [ -n "$tls_usage" ]; then
    non_compliant_tls=""
    while IFS= read -r file; do
        if ! grep -q -i "BCJSSE\|BouncyCastleProvider\|bouncycastle" "$file" 2>/dev/null; then
            non_compliant_tls="$non_compliant_tls$file"$'\n'
        fi
    done <<< "$tls_usage"
    
    if [ -n "$non_compliant_tls" ]; then
        echo "$non_compliant_tls" | grep .
        echo ""
    fi
fi

# Check 6: Insecure random number generation
echo "Checking: Insecure random number generation"
insecure_random=$(grep -r --include="*.java" \
    -E "new\s+java\.util\.Random\s*\(" . 2>/dev/null | \
    grep -v "\.git/" | grep -v "SecureRandom" | cut -d: -f1 | sort -u | filter_test_files)

if [ -n "$insecure_random" ]; then
    echo "$insecure_random"
    echo ""
fi

# Check 7: Key generation and manipulation
echo "Checking: Key generation and manipulation"
keygen_files=$(search_java_files '(KeyGenerator|KeyPairGenerator|KeyFactory|KeyStore|loadKey|generateKey|loadPrivate|loadPublic)')
if [ -n "$keygen_files" ]; then
    echo "$keygen_files"
    echo ""
fi

# Check 8: Cryptographic package imports
echo "Checking: Cryptographic package imports"
crypto_packages_files=$(grep -r --include="*.java" \
    -E "import\s+($CRYPTO_PACKAGES)" . 2>/dev/null | \
    grep -v "\.git/" | cut -d: -f1 | sort -u | filter_test_files)

if [ -n "$crypto_packages_files" ]; then
    echo "$crypto_packages_files"
    echo ""
fi

# Check 9: FIPS-related keywords
echo "Checking: FIPS-related keywords"
fips_keywords_files=$(grep -r --include="*.java" \
    -E "($FIPS_KEYWORDS)" . 2>/dev/null | \
    grep -v "\.git/" | cut -d: -f1 | sort -u | filter_test_files)

if [ -n "$fips_keywords_files" ]; then
    echo "$fips_keywords_files"
    echo ""
fi

# Check 10: Weak cipher suites
echo "Checking: Weak cipher suites"
cipher_config_files=$(grep -r --include="*.java" --include="*.properties" --include="*.xml" \
    -E "(DES|RC4|RC2|NULL|ANON|EXPORT|SSLv2|SSLv3|TLSv1\.0)" . 2>/dev/null | \
    grep -v "\.git/" | cut -d: -f1 | sort -u | filter_test_files)

if [ -n "$cipher_config_files" ]; then
    echo "$cipher_config_files"
    echo ""
fi

# Check 11: Certificate validation and handling
echo "Checking: Certificate validation and handling"
cert_files=$(search_java_files '(Certificate|X509Certificate|CertificateFactory|TrustManager|checkServerTrusted|checkClientTrusted)')
if [ -n "$cert_files" ]; then
    echo "$cert_files"
    echo ""
fi

# Check 12: BouncyCastle FIPS provider usage
echo "Checking: BouncyCastle FIPS provider usage"
bc_fips_files=$(grep -r --include="*.java" --include="pom.xml" --include="build.gradle" \
    -E "(BCFIPS|org\.bouncycastle.*fips|bc-fips)" . 2>/dev/null | \
    grep -v "\.git/" | cut -d: -f1 | sort -u | filter_test_files)

if [ -n "$bc_fips_files" ]; then
    echo "$bc_fips_files"
    echo ""
fi

# Check 13: java.security configuration and properties
echo "Checking: java.security configuration files"
java_security_files=$(find . -name "java.security*" -type f 2>/dev/null | grep -v "\.git/")
if [ -n "$java_security_files" ]; then
    echo "$java_security_files"
    echo ""
fi

echo "Checking: java.security property configuration"
java_security_props=$(grep -r --include="*.java" \
    -E '(System\.setProperty\s*\(\s*"java\.security|System\.getProperty\s*\(\s*"java\.security|java\.security\.)' . 2>/dev/null | \
    grep -v "\.git/" | cut -d: -f1 | sort -u | filter_test_files)

if [ -n "$java_security_props" ]; then
    echo "$java_security_props"
    echo ""
fi

echo "Checking: Security provider registration"
provider_registration=$(grep -r --include="*.java" \
    -E "(Security\.addProvider|Security\.insertProviderAt|Provider|getInstance.*Provider)" . 2>/dev/null | \
    grep -v "\.git/" | cut -d: -f1 | sort -u | filter_test_files)

if [ -n "$provider_registration" ]; then
    echo "$provider_registration"
    echo ""
fi

echo "===================================="
echo "Scan complete"
