FROM cgr.dev/chainguard-private/jdk:latest-dev

USER 0
RUN apk add --no-cache maven
USER 65532

WORKDIR /src

# https://downloads.bouncycastle.org/java/docs/PQC-Almanac.pdf
COPY pom.xml .
COPY PQCTest.java src/main/java/PQCTest.java

RUN mvn -B dependency:resolve package -DskipTests

ENTRYPOINT ["java", "-cp", "target/classes:target/dependency/*", "PQCTest"]