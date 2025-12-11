#Define Chainguard org to pull images from
ARG CHAINGUARD_ORG

# BUILD STAGE: Use Chainguard distroless go variant for build stage. You may optionally switch to -dev if additional utilities are needed to build your app.
FROM cgr.dev/${CHAINGUARD_ORG}/go:latest AS build

# Set working directory
WORKDIR /helloworld

# Copy dependencies list
COPY go.mod go.sum ./

# Build
COPY main.go .
RUN go build -o main main.go

# FINAL STAGE: Copy artifacts to a clean image. Chainguard recommends using glibc-dynamic or static as a runtime for go applications. For more info, visit https://images.chainguard.dev/directory/image/go/overview#compatibility-notes
FROM cgr.dev/${CHAINGUARD_ORG}/glibc-dynamic
COPY --from=build /helloworld/main /main
ENTRYPOINT [ "/main" ]
