# jlink and Java 11+ with FIPS

## Background

Java 11+ are modularised, and support jlink to create custom runtimes.

jlink does not supported signed modules as of right now any any java
version[1](https://github.com/bcgit/bc-java/issues/1537#issuecomment-1837818587).

Preserving signatures of the bc-fips.jar is required for completing
FIPS self-tests and operate in FIPS mode.

## Solution

Create jlink for your applications and modules, **without bc-fips jars**.

At runtime, **specify --module-path** to bc-fips jars, on Chainguard FIPS Images that would be:

```
path/to/jlinked/jre/java --module-path=/usr/share/java/bouncycastle-fips -Djavax.net.ssl.trustStoreType=FIPS -jar /app/your-app.jar
```

## Example

A detailed example based on the springboot example to follow.
