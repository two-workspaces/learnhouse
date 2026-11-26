# Upstream's LearnHouse image (web app, API, collaboration server and nginx in one),
# pinned to a release. The wrapper only adds the Railway entrypoint and the page-cache
# trimmer; python3 is already in the image for it.
FROM ghcr.io/learnhouse/app:1.4.5

COPY --chmod=0755 railway-entrypoint.sh drop-file-cache /usr/local/bin/

CMD ["/usr/local/bin/railway-entrypoint.sh"]
