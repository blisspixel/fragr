# Join menu and run menu

Status: **implemented**, 2026-10-06. Not merged, and not a release.

## Goal

On Multiplayer, running a server and joining a server are separate. Check host
reads the address in the join field and leaves that address in place.

## What was wrong

The join page stacked **Check host** and **Check server on this computer**.
The second button replaced the address with the owned server, or with
`127.0.0.1:6767`, and then probed. A typed address disappeared. The field
above those buttons was labeled Host, next to Host a match.

The host page already watches, joins, and stops a server started in the app.
That page uses the owned URL and does not read the join field.

## Behavior

**Run a server** is its own heading and button. It opens the existing host
page. While a server started in this app is running, the button says Your
server and the line above it says the server is still running. Watch, Join,
and Stop stay on that page.

**Join a server** is the address field, Check host, Watch, and Join. The
field starts from `FRAGR_SERVER` when that is set, otherwise
`127.0.0.1:6767`. An owned server does not replace it. Text the player types
is kept when the page is rebuilt, including a trip to the run page and back.
Check host probes that field only. The local book and LAN announcement are
[server list](server-list.md), not this split.

Failure sentences stay the ones in [join preflight](join-preflight.md). A
missing status is still exactly "This host did not answer."

## Non-goals

No new mode, no Wipe, no Terraform, no tick change, and no measurement table.
No changelog entry until a release is cut. No change to the dedicated process
that is already running. Screenshot tour stays until a release cut.

## Architecture

Menu construction stays in `client/scripts/boot_menu.gd`. Copy is in
`client/i18n/world.en.po`. No protocol, server, or capability change.

## Verification

Godot 4.7.2.stable headless, 2026-10-06, on this machine:

- `test_host_menu.gd`: PASS. A running owned server stays on its own page. The typed address is not the owned URL, survives that page, and nothing named UseRunningServer remains.
- `test_frontend.gd`: PASS. Idle Multiplayer labels Run a server and Join a server separately. A typed address survives the run page. The missing-status sentence stays "This host did not answer."

The full `tools/godot_check.sh` suite was not run. Spend is $0.

## Success

A typed join address is still there after Check host and after opening the
run page. The join page has no control that writes the owned server into
that field.
