FROM busybox:1.38@sha256:a46257e06c82ad85242d0d38077d0a52d9896389ca60a1a59d3463db586e5fa4
USER 1000
COPY owned /owned
USER 0
RUN --mount=type=secret,id=github_token test -s /run/secrets/github_token
