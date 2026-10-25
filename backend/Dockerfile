FROM dart:stable AS build

WORKDIR /app
COPY pubspec.yaml ./
RUN dart pub get

COPY bin ./bin
COPY lib ./lib
RUN dart compile exe bin/server.dart -o /app/server

FROM debian:bookworm-slim
COPY --from=build /app/server /usr/local/bin/server
ENV PORT=8080
ENV DATA_DIR=/data
EXPOSE 8080
VOLUME /data
ENTRYPOINT ["server"]