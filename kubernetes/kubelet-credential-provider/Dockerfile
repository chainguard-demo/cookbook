FROM cgr.dev/chainguard/go:latest AS build

COPY go.mod go.mod
COPY go.sum go.sum
RUN go mod download

COPY main.go main.go
RUN go build -o /usr/local/bin/cgr-credential-provider .

FROM kindest/node:v1.33.0

COPY --from=build /usr/local/bin/cgr-credential-provider /usr/local/bin/cgr-credential-provider
