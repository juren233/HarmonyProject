FROM dart:3.6 AS build
WORKDIR /workspace
COPY packages/petnote_sync_protocol /workspace/packages/petnote_sync_protocol
COPY server /workspace/server
WORKDIR /workspace/server
RUN dart pub get && dart compile exe bin/petnote_sync_server.dart -o /petnote_sync_server

FROM debian:bookworm-slim
COPY --from=build /petnote_sync_server /usr/local/bin/petnote_sync_server
ENV PORT=8787 DATA_DIR=/data
VOLUME /data
EXPOSE 8787
ENTRYPOINT ["/usr/local/bin/petnote_sync_server"]
