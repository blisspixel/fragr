# Immediate snapshot writes

**Status:** implemented in source (2026-10-06). The focused socket test passed. Not merged. The running night process was built at 07:39 and does not have this. It was left running: today's source speaks gameplay 37, and the published client speaks 36.

## Goal

An accepted game socket sends each write immediately, so the short tail of a snapshot is not held for an acknowledgement.

## Non-goals

A new transport, a snapshot-rate change, or replacing the live night process in this change. The client already disables Nagle in Godot 4.7. The two-tick presentation buffer stays.

## Architecture

`disable_nagle` runs on the accepted `TcpStream` before status classification or the WebSocket handshake. A failure is logged and the socket stays up.

## Protocol or API

None. The bytes are unchanged. They leave sooner.

## Verification

`accepted_socket_disables_nagle` accepts a loopback socket, checks that Nagle starts on, and checks that the helper turns it off.

## Spend

$0.

## Success

A quiet LAN no longer waits on the delayed acknowledgement for the end of each world snapshot. That wait was a likely part of the 2026-10-06 report from `192.168.44.80`. The server tick that morning stayed under budget (p50 about 0.13 ms, zero ticks over 50 ms) with one human connected, so the sim itself was not the stall.
