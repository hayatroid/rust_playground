FROM criyle/go-judge:latest
RUN apt-get update && apt-get install -y --no-install-recommends rustc
COPY --chmod=755 entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
