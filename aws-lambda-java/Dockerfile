ARG CHAINGUARD_ORG="chainguard"

# Use the Chainguard maven image during the build stage
FROM cgr.dev/${CHAINGUARD_ORG}/maven:latest AS build-image

# Configure the build environment
WORKDIR /src

# Cache and copy dependencies
COPY pom.xml .
RUN mvn dependency:go-offline dependency:copy-dependencies

# Compile the function
COPY . .
RUN mvn package 

# Copy the function artifact and dependencies onto a clean base
FROM cgr.dev/${CHAINGUARD_ORG}/jre
WORKDIR /function

COPY --from=build-image /src/target/dependency/*.jar ./
COPY --from=build-image /src/target/*.jar ./

# Set runtime interface client as default command for the container runtime
ENTRYPOINT [ "/usr/bin/java", "-cp", "./*", "com.amazonaws.services.lambda.runtime.api.client.AWSLambda" ]
# Pass the name of the function handler as an argument to the runtime
CMD [ "example.App::sayHello" ]