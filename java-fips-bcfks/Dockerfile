# ----------------------------------------------------------
# Single-stage on Chainguard Corretto JDK FIPS
# ----------------------------------------------------------
ARG JDK_FIPS_IMAGE=cgr.dev/chainguard-private/amazon-corretto-jdk-fips
ARG JDK_FIPS_TAG=11-dev
FROM ${JDK_FIPS_IMAGE}:${JDK_FIPS_TAG} AS prep

ARG APP_NAME=web-backend
ARG DIST_TAR=dist.tar.gz

USER root

# Tools used at build/runtime (openssl needed by run.sh for PKCS#8 conversion)
RUN apk update && apk --no-cache add \
      curl unzip ca-certificates \
      python3 shadow iptables glibc-locale-en ipset findutils \
      openssl nss libxml2 zlib cups-libs

# App layout
RUN mkdir -p /app /app/tmp /app/certs /var/app
COPY /app/certs/ /app/certs/

# Bring in your distribution tarball
COPY ${DIST_TAR} /tmp/dist.tar

# Unpack app and set a stable symlink to the entry binary
RUN set -e \
 && tar -xf /tmp/dist.tar --strip-components 1 -C /app \
 && rm -f /tmp/dist.tar \
 && ln -sf /app/bin/${APP_NAME} /app/bin/app-entry

# Ensure run.sh is executable if present
RUN [ -f /app/bin/run.sh ] && chmod 755 /app/bin/run.sh || true

# Users / perms
RUN addgroup -g 1001 app && addgroup -g 2001 app2 \
 && adduser -D -H -u 1001 -G app  app \
 && adduser -D -H -u 2001 -G app2 app2 \
 && adduser app  app2 && adduser app2 app \
 && chown -R app:app /app /var/app \
 && chmod 775 /var/app /app/tmp /app/certs /etc

# ---------- Runtime env ----------
ENV APP_JAR=/app/lib/app.jar
ENV LANG=en_US.utf8
ENV LC_ALL=en_US.utf8

# Expose BC-FIPS modules; do not add any javax.net.ssl.* pins here
# Expose BC-FIPS modules (no java.security override; no append file)
ENV JDK_JAVA_OPTIONS="--module-path=/usr/share/java/bouncycastle-fips --add-modules=jdk.crypto.ec,jdk.crypto.cryptoki ${JDK_JAVA_OPTIONS}"
ENV JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS}"

# Optional FIPS toggles (OpenSSL at OS level; BC approved-only if you set FIPS_APPROVED_ONLY at runtime)
ENV AWS_USE_FIPS_ENDPOINT="true"
# Do NOT force OpenSSL FIPS here; we only use openssl for -topk8 -nocrypt (FIPS-safe).
# ENV OPENSSL_FORCE_FIPS_MODE=1

# Hints for scripts; harmless
ENV PROVIDER="org.bouncycastle.jcajce.provider.BouncyCastleFipsProvider"
ENV PROVIDER_PATH_PATTERN="/usr/share/java/bouncycastle-fips/bc-fips.jar"

# Java home path (Chainguard default)
ENV JAVA_HOME="/usr/lib/jvm/default-jvm"

USER app
WORKDIR /app
EXPOSE 8080

ENTRYPOINT ["/app/bin/run.sh"]