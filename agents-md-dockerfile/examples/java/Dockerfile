FROM maven:3.9-eclipse-temurin-17 as build-env

WORKDIR /app

COPY pom.xml .
COPY src ./src

RUN mvn clean package -DskipTests

FROM gcr.io/distroless/java17-debian12

ENV HOST 0.0.0.0
ENV PORT 8080

WORKDIR /app

COPY --from=build-env /app/target/test-java-app-1.0.0.jar .

USER nonroot

EXPOSE 8080

CMD ["test-java-app-1.0.0.jar"]
