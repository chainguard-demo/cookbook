FROM cgr.dev/chainguard/go:latest AS builder
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build \
    -trimpath \
    -ldflags="-s -w" \
    -o /out/renovate-datasource \
    ./cmd/renovate-datasource

FROM cgr.dev/chainguard/static:latest
COPY --from=builder /out/renovate-datasource /usr/local/bin/renovate-datasource
EXPOSE 8080
USER nonroot
ENTRYPOINT ["/usr/local/bin/renovate-datasource"]
