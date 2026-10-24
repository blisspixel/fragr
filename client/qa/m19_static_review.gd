extends "res://scripts/qa_tour.gd"

## Planned Works static review: a spectator on the level's own server takes
## fixed stills of each space (concourse, stair, tram street, market, court,
## tanks, roofs, workshop, trench, river) to judge light and dressing without
## waiting for a live run. Geometry and lighting only: no encounter is active.
##
## Run against `fragr-server --bots 0 --map-file server/maps/m19-planned-works.json`
## on a real display with `FRAGR_QA_MANIFEST=<abs path to client/qa/m19-static-review.json>`
## and `FRAGR_QA_DIR=<out>`: `godot --path client --script res://qa/m19_static_review.gd`.

## A tiling desktop resizes the window; stills keep the screen's own aspect,
## so the tour's fixed-size gate does not apply here.
func _ensure_capture_window_size(_label: String) -> bool:
	if root.mode != Window.MODE_FULLSCREEN:
		root.mode = Window.MODE_FULLSCREEN
	return true
