# Home and LAN dedicated host

The Rust server owns one match. Run it on a machine you control and give
friends that machine's address. The current game port is **TCP 6767** for
WebSocket. UDP is reserved for a measured future transport and the container
does not publish it yet. No cloud account or external API charge is needed.

## Start with Docker Compose

From the repository root, with Docker running:

```bash
docker compose up --build -d
docker compose ps
```

The image compiles the locked Rust server, embeds the shipped maps and carries
fragr's license and the linked crates' notices under `/usr/share/doc/fragr`.
Compose
starts four rule bots on Arena Duel, restarts the process if it exits, and
checks that `GET /status` reports `health.status: ok` from inside the
container. Wait until `docker compose ps`
shows `healthy`. Confirm the host can read `http://127.0.0.1:6767/status`.
The health reply is an operator probe, not a player or agent protocol.

```bash
docker compose logs --tail=100 server
docker compose down
```

Set `FRAGR_BOTS` or `FRAGR_MAP` in the shell or a repository-root `.env` before
starting Compose to change the roster or map. `.env` is ignored by Git. To
select a rule set, use a local Compose override that replaces the `command`
array with the server's documented CLI flags. Do not put join secrets in the
image, command, or a committed override.

The container runs as a non-root user with a read-only root filesystem and
publishes TCP 6767. It writes no campaign run file. Local Single Player owns
its separate loopback process and run storage; do not point that menu at the
dedicated container.

## Connect

- On the same machine, the Godot client can use `127.0.0.1:6767`.
- On a LAN, use the host's LAN address, such as `192.168.x.x:6767`. Allow TCP
  6767 through the host firewall only for the LAN subnet if this is a private
  match.
- A trusted-friends internet test can forward **TCP 6767** on the router to
  the host and give joiners the public IP or DNS name. The direct `ws://`
  connection is plaintext. Limit the source addresses at the firewall where
  possible and do not treat a shared join secret over that connection as
  protected. A stranger-facing service needs TLS, ticket distribution and a
  public abuse and recovery test before it is ready. If your ISP uses CGNAT or
  double NAT, a small host with a public address is an alternative in
  [CHEAP-VPS.md](CHEAP-VPS.md).

The app's Multiplayer page and `FRAGR_SERVER` accept the host address.
The adapter connects to the configured WebSocket endpoint. Tailscale can be
used for a private test, but is not required for the public join path.

## Admission and access files

An unset or empty `FRAGR_JOIN_SECRET` leaves player admission open. To require
join tickets, set one 16 to 256 byte value as an environment variable on the
host and on each human or agent client. Compose passes it to the server.
Spectators can still watch. The client and host clocks must agree within about
15 seconds. Do not reuse a valuable secret on a plaintext public connection.
Configure transport security before relying on tickets for public admission.

The server accepts `--ban-list` and `--allow-list` file paths. For a container,
mount the files read-only and pass their **container paths** in a local Compose
override. Do not mount an entire secret directory or include the files in the
image. Invalid lists refuse startup; bad reloads keep the last valid list.
Addresses and CIDR ranges are checked before a session takes a seat.

`docker compose logs server` shows joins, rejections and health diagnostics.
Keep SSH closed to the public internet. The [hosting plan](../../docs/plans/dedicated-server-udp-and-hosting.md)
records the later TLS, measured transport and cloud gates.

## Without Docker

```bash
cargo run -p fragr-server --locked -- --bind 127.0.0.1:6767 --bots 4
```

For LAN peers, bind `0.0.0.0:6767` and apply the same firewall rule. The
desktop client and adapter use exactly the same wire as the container host.
