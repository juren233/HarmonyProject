ARG DART_IMAGE=dart:3.6
ARG RUNTIME_IMAGE=debian:bookworm-slim
ARG PUB_HOSTED_URL=https://pub.dev

FROM ${DART_IMAGE} AS build
ARG PUB_HOSTED_URL
ENV PUB_HOSTED_URL=${PUB_HOSTED_URL}
WORKDIR /workspace
COPY packages/petnote_sync_protocol /workspace/packages/petnote_sync_protocol
COPY server /workspace/server
WORKDIR /workspace/server
RUN dart pub get && dart compile exe bin/petnote_sync_server.dart -o /petnote_sync_server

FROM ${RUNTIME_IMAGE}
COPY --from=build /petnote_sync_server /usr/local/bin/petnote_sync_server
ENV PORT=8787 DATA_DIR=/data
VOLUME /data
EXPOSE 8787
ENTRYPOINT ["/usr/local/bin/petnote_sync_server"]
