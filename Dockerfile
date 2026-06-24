FROM golang:1.25-alpine AS builder

WORKDIR /build
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o llm-proxy .

FROM alpine:3.21

RUN apk add --no-cache ca-certificates tzdata

WORKDIR /app
COPY --from=builder /build/llm-proxy .

EXPOSE 9090

VOLUME ["/data"]

ENTRYPOINT ["./llm-proxy"]
CMD ["-config", "/data/config.yaml"]
