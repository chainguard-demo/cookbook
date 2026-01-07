FROM golang:1.23-alpine as build-env

WORKDIR /app

COPY go.mod ./
COPY main.go ./

RUN go build -o server main.go

FROM gcr.io/distroless/static-debian12

ENV HOST 0.0.0.0
ENV PORT 8080

WORKDIR /app

COPY --from=build-env /app/server .

USER nonroot

EXPOSE 8080

CMD ["/app/server"]
