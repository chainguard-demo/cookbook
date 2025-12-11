#Define Chainguard org to pull images from
ARG CHAINGUARD_ORG

# BUILD STAGE: Use Chainguard distroless dev variant for build stage. You may optionally switch to -dev if additional utilities are needed to build your app.
FROM cgr.dev/${CHAINGUARD_ORG}/rust:latest AS build-image

# Set working directory
WORKDIR /app

# Copy code
COPY . .

# Build the app
RUN cargo build --release

# FINAL STAGE: Copy artifacts to a clean image. Chainguard recommends using glibc-dynamic or static as a runtime for rust applications. For more info, visit https://images.chainguard.dev/directory/image/rust/overview#application-setup-for-end-users
FROM cgr.dev/${CHAINGUARD_ORG}/glibc-dynamic

# Copy the built binary to the runtime image. The name of your binary will likely differ as it is dicated by your Cargo.toml, so please adjust this accordingly.
COPY --from=build-image /app/target/release/aws-lambda-rust /usr/local/bin/aws-lambda-rust

ENTRYPOINT ["/usr/local/bin/aws-lambda-rust"]
