# Client release check

**Status:** implemented in source (2026-10-06). Not merged. `test_release_install.gd`, `test_frontend.gd`, `test_server_book.gd`, and `test_host_menu.gd` passed headless on Godot 4.7.2. The older-client refusal sentence was already covered by `an_older_client_is_sent_to_the_release_and_its_checksum`. The full client checker was not re-run. The running night process does not offer this until it is replaced. A published v0.78 client has no install button.

## Goal

A client that does not speak the server's gameplay or geometry version is told where to get a matching desktop build, and how to check that download. When this client is the one behind, the join page offers to install the latest published archive, check it against `SHA256SUMS.txt`, and rejoin that host.

## Non-goals

A phone-home, a fetch of GitHub during join, or a hash of the running game. The offer starts only after the player chooses it. Editor play, agents, and a source build have no published archive hash. A matching hello is admitted with no extra check. A missing `gameplay_version` on `GET /status` still does not warn or block. Watch and Join stay available after a warning. The latest tag is not claimed to speak the number this process requires. The editor and a source checkout are not overwritten.

## Architecture

The server already refuses a hello outside its contract. When the hello is older than the floor, the error names the required version and the releases page. The checksum file on that page is `SHA256SUMS.txt`. A newer hello is still told which version this process speaks, without being sent to replace itself.

The join page reads the same versions from `GET /status`. A higher advertised version asks this client to update and shows **Install the latest and rejoin**. A lower one says the server is older and shows no install button. Nothing is downloaded until the button is pressed.

The offer reads the public latest release, picks this computer's archive (`fragr-<tag>-windows-x86_64.zip`, `linux-x86_64`, or `macos-universal`), downloads `SHA256SUMS.txt` and that zip, and starts the game only when the zip's hash matches the named line. Download URLs are built for `github.com/blisspixel/fragr`. A URL inside the release JSON is ignored. The new process is started with `--rejoin` so it joins as the player. `FRAGR_SERVER` alone would still watch.

An exported `fragr.exe`, `fragr.x86_64`, or `fragr.app` outside a checkout can be replaced after this process exits, because Windows cannot overwrite a running executable. The editor, a Godot binary, and any folder inside the source checkout launch the checked copy beside them instead. A checksum mismatch is not unpacked into a launch.

If the error text arrives on the socket, the client shows it and adds the release sentence when the server only said to update. A close that carries only the code still names the releases page.

## Protocol or API

No new field. `ops.version` and the gameplay contract stay as they are. The older-client message names `https://github.com/blisspixel/fragr/releases/latest` and `SHA256SUMS.txt`. `--rejoin <host>` is a client argument, not a server message.

## Verification

`an_older_client_is_sent_to_the_release_and_its_checksum` checks the older and newer sentences. `test_server_book.gd` and `test_frontend.gd` cover a higher advertised version, an older server, and a missing version. The join page shows the install button only when this client is behind, leaves Watch and Join enabled, and does not create a download until the button is chosen. `test_kick_reasons.gd` checks that a safe update sentence keeps the link and a junk sentence does not replace the fallback.

`test_release_install.gd` uses local fixtures. It checks archive names, that a foreign asset URL is ignored, checksum lines, a mismatch that does not unpack, a parent path that is not written, and that the editor, a Godot binary, and a source checkout are not the folder that gets replaced. It does not call GitHub. Those four client harnesses passed on 2026-10-06. `tools/godot_check.sh` was not re-run.

## Spend

$0. The offer uses the public release. It does not use a paid API.

## Success

A player on an older client can read the releases page, or choose to install the checked latest archive and rejoin the host they were looking at. A current client on a quiet LAN is not asked to reach GitHub. A bad checksum does not start. Installing the latest published tag can still leave the player behind a newer server, and the page says so.
