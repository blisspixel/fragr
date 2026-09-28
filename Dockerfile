# syntax=docker/dockerfile:1
FROM rust:1.98.1-bookworm AS build

WORKDIR /src
COPY . .
RUN cargo build -p fragr-server --release --locked
RUN target="$(rustc -vV | sed -n 's/^host: //p')" \
    && cargo run -p fragr-licenses --locked -- \
       --target "$target" --deny deny.toml --out /tmp/THIRD_PARTY_LICENSES.txt

FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 10001 fragr \
    && useradd --uid 10001 --gid 10001 --no-create-home --shell /usr/sbin/nologin fragr

COPY --from=build /src/target/release/fragr-server /usr/local/bin/fragr-server
COPY LICENSE /usr/share/doc/fragr/fragr-LICENSE.txt
COPY --from=build /tmp/THIRD_PARTY_LICENSES.txt /usr/share/doc/fragr/THIRD_PARTY_LICENSES.txt
USER 10001:10001
EXPOSE 6767/tcp
STOPSIGNAL SIGTERM
ENTRYPOINT ["/usr/local/bin/fragr-server"]
CMD ["--bind", "0.0.0.0:6767", "--bots", "4"]
