FROM golang:1.22.4-alpine AS build
WORKDIR /src

COPY go-sample-app/go.mod ./go.mod
COPY go-sample-app/main.go ./main.go

RUN CGO_ENABLED=0 GOOS=linux go build -o /out/app ./main.go

FROM gcr.io/distroless/static-debian12
WORKDIR /app
COPY --from=build /out/app /app/app

EXPOSE 8080
ENTRYPOINT ["/app/app"]
