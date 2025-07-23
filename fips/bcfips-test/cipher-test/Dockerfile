# Use Chainguard JDK FIPS-compliant base image
FROM cgr.dev/chainguard-private/jdk-fips:latest as builder

# Set working directory
WORKDIR /src

# Copy Java source file into container
COPY BadCipherTest.java .

RUN javac BadCipherTest.java  && \
    jar cvf bcfips-test.jar *.class

ENTRYPOINT ["java", "-cp", "bcfips-test.jar", "BadCipherTest"]

