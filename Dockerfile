FROM node:20-bookworm-slim AS frontend-builder
WORKDIR /app/frontend

COPY frontend/package*.json ./
RUN npm ci

COPY frontend/ ./
RUN npm run build

FROM golang:1.23-bookworm AS backend-builder
WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends build-essential && rm -rf /var/lib/apt/lists/*

COPY go.mod go.sum ./
RUN go mod download

COPY . .
COPY --from=frontend-builder /app/frontend/dist ./frontend/dist

RUN CGO_ENABLED=1 GOOS=linux go build -o /out/server ./cmd/web

FROM debian:bookworm-slim
WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*

COPY --from=backend-builder /out/server ./server
COPY --from=backend-builder /app/frontend/dist ./frontend/dist
COPY --from=backend-builder /app/internal/dictionary/Database/balochi_dict.db ./internal/dictionary/Database/balochi_dict.db

ENV PORT=8080
EXPOSE 8080

CMD ["./server"]
