# Define custom function directory
ARG FUNCTION_DIR="/var/task"

# Define Chainguard org to pull images from
ARG CHAINGUARD_ORG="[INSERT CHAINGUARD ORG]"

FROM cgr.dev/${CHAINGUARD_ORG}/dotnet-sdk:9 AS build-image

# Set temporary directory in builder 
WORKDIR /tmp

# Copy function code to build-image
COPY chainguard-lambda-runtimes-dotnet-example.csproj .
COPY Function.cs .

# Change to root user
USER 0

# Build the application
RUN dotnet publish chainguard-lambda-runtimes-dotnet-example.csproj \
    --configuration Release \
    --output build

# Use the Chainguard dotnet-runtime image as the runtime
FROM cgr.dev/${CHAINGUARD_ORG}/dotnet-runtime:9

# Include global arg in this stage of the build
ARG FUNCTION_DIR

# Set working directory to function root directory
WORKDIR ${FUNCTION_DIR}
  
# Copy built app to runtime image
COPY --from=build-image /tmp/build  .
  
# Set the entrypoint to the bootstrap
ENTRYPOINT ["/usr/bin/dotnet", "exec", "/var/task/bootstrap.dll"]