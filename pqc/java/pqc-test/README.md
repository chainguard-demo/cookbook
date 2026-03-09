# List BCPQC Provider Algorithm Support

Print the supported [NIST PQC Algorithms](https://csrc.nist.gov/projects/post-quantum-cryptography#pqc-standards) (FIPS 203, FIPS 204, FIPS 205) in the [BouncyCastle BCPQC Provider](https://github.com/bcgit/bc-java/blob/main/prov/src/main/java/org/bouncycastle/pqc/jcajce/provider/BouncyCastlePQCProvider.java)

## Basic Usage

```bash
docker build -t pqc:cgr .
docker run pqc:cgr
```

## Alternative Option

Run Example 1 from the (BouncyCastle PQC Almanac)[https://downloads.bouncycastle.org/java/docs/PQC-Almanac.pdf] by overwriting PQCTest.java with PQC-Almanac-Ex1.java

## Example Output

```
=================================================
  BCPQC Provider Algorithm Listing
=================================================
  Provider : BouncyCastle Post-Quantum Security Provider v1.83
  Version  : 1.83
-------------------------------------------------

  [KeyPairGenerator]
    ML-KEM
    ML-KEM-1024
    ML-KEM-512
    ML-KEM-768

  [KeyGenerator]
    ML-KEM-1024
    ML-KEM-512
    ML-KEM-768

  [KeyFactory]
    ML-KEM-1024
    ML-KEM-512
    ML-KEM-768

  [Cipher]
    ML-KEM-1024
    ML-KEM-512
    ML-KEM-768
```