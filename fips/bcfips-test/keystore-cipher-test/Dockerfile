FROM cgr.dev/chainguard-private/jdk-fips:latest

# Set working directory
WORKDIR /src

# Copy Java source file into container
COPY BadCipherTestv2.java .
COPY client-keystore.p12 .
COPY truststore.p12 .

RUN javac BadCipherTest-v2.java  && \
    jar cvf bcfips-test.jar *.class

ENTRYPOINT ["java", "-cp", "bcfips-test.jar", "BadCipherTest"]

