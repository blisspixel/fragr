class_name SealCutPlate
extends Control

## Signature moment: Seal Cut (arrival, join, round start).
## The status bar plates and match strip arrive as a Union-issued object:
## a riveted plate with stencil marks and a union_red (#8c1a1e) tamper seal across readouts.
## In 3-4 stepped frames (~300ms), seal is cut, stencil is scratched, and plate settles
## to bare scarred gunmetal with bone numerals. Numbers are readable in all frames.
## Respawn shows final frame only. Reduced motion shows final frame immediately.
## Side-aware: Union allegiance has opposite beat (seal presses on, inspection checkmark ticks in).

const TOTAL_DURATION: float = 0.30
const FRAME_COUNT: int = 4
const FRAME_DURATION: float = 0.075
const UNION_RED: Color = Color("8c1a1e")

var allegiance: String = "coalition" # "union" or "coalition" (free)
var current_frame: int = 3 # 0..3, default settled
var is_playing: bool = false
var elapsed: float = 0.0
var settled: bool = true

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## Start or replay the stepped arrival moment.
func play_seal_cut(p_allegiance: String, reduced_motion: bool = false) -> void:
	allegiance = p_allegiance
	if reduced_motion:
		settled = true
		is_playing = false
		current_frame = 3
		queue_redraw()
		return

	settled = false
	elapsed = 0.0
	current_frame = 0
	is_playing = true
	queue_redraw()

## Settle immediately to final frame (e.g. on respawn).
func settle(p_allegiance: String = "") -> void:
	if not p_allegiance.is_empty():
		allegiance = p_allegiance
	settled = true
	is_playing = false
	current_frame = 3
	queue_redraw()

func _process(delta: float) -> void:
	if not is_playing:
		return
	elapsed += delta
	var frame: int = clampi(int(elapsed / FRAME_DURATION), 0, FRAME_COUNT - 1)
	if frame != current_frame:
		current_frame = frame
		queue_redraw()
	if elapsed >= TOTAL_DURATION:
		settled = true
		is_playing = false
		current_frame = 3
		queue_redraw()

func _draw() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	if rect.size.x < 4.0 or rect.size.y < 4.0:
		return

	# 1. Base gunmetal plate: dark bevel perimeter, inset plate surface, corner rivets
	draw_rect(rect, MenuTheme.INK)
	draw_rect(rect.grow(-1.0), MenuTheme.EDGE)
	draw_rect(rect.grow(-3.0), MenuTheme.INSET)

	# Rivets at 4 corners
	var rivet_color: Color = MenuTheme.BORDER
	var shadow_color: Color = MenuTheme.INK
	var r_sz: float = 3.0
	var rivet_positions: Array[Vector2] = [
		Vector2(4, 4),
		Vector2(rect.size.x - 7, 4),
		Vector2(4, rect.size.y - 7),
		Vector2(rect.size.x - 7, rect.size.y - 7),
	]
	# Additional rivets if plate is wide (e.g. > 160px)
	if rect.size.x > 160.0:
		rivet_positions.append(Vector2(rect.size.x * 0.5 - 1.5, 4))
		rivet_positions.append(Vector2(rect.size.x * 0.5 - 1.5, rect.size.y - 7))

	for pos: Vector2 in rivet_positions:
		draw_rect(Rect2(pos + Vector2(1, 1), Vector2(r_sz, r_sz)), shadow_color)
		draw_rect(Rect2(pos, Vector2(r_sz, r_sz)), rivet_color)

	# 2. Dressing: Tamper seal, stencil, scratch marks based on allegiance & frame
	var is_union: bool = allegiance == "union"

	if not is_union:
		_draw_free_sequence(rect)
	else:
		_draw_union_sequence(rect)

func _draw_free_sequence(rect: Rect2) -> void:
	var seal_w: float = minf(72.0, rect.size.x * 0.3)
	var seal_h: float = 10.0
	var seal_x: float = rect.size.x - seal_w - 12.0
	var seal_y: float = 3.0

	match current_frame:
		0:
			# Frame 0: Intact union_red tamper seal & stencil registration mark
			draw_rect(Rect2(seal_x, seal_y, seal_w, seal_h), UNION_RED)
			# Stencil markings (fine ink hashes on seal)
			for i: int in range(4):
				var hx: float = seal_x + 8.0 + float(i) * 14.0
				draw_line(Vector2(hx, seal_y + 2), Vector2(hx + 4, seal_y + seal_h - 2), MenuTheme.INK, 1.0)
			# Asset registration stencil on top-left edge
			draw_rect(Rect2(16, 5, 24, 2), MenuTheme.MUTED)
			draw_rect(Rect2(44, 5, 12, 2), MenuTheme.MUTED)

		1:
			# Frame 1: Sharp blade cut slices through tamper seal; scratch through stencil
			draw_rect(Rect2(seal_x, seal_y, seal_w, seal_h), UNION_RED)
			for i: int in range(4):
				var hx: float = seal_x + 8.0 + float(i) * 14.0
				draw_line(Vector2(hx, seal_y + 2), Vector2(hx + 4, seal_y + seal_h - 2), MenuTheme.INK, 1.0)
			# Blade slice cut across center of seal
			var cut_x: float = seal_x + seal_w * 0.48
			draw_line(Vector2(cut_x - 3, seal_y - 1), Vector2(cut_x + 3, seal_y + seal_h + 1), MenuTheme.INK, 2.0)
			draw_line(Vector2(cut_x - 2, seal_y), Vector2(cut_x + 2, seal_y + seal_h), MenuTheme.BORDER, 1.0)
			# Scratched stencil
			draw_rect(Rect2(16, 5, 24, 2), MenuTheme.MUTED)
			draw_line(Vector2(14, 4), Vector2(38, 8), MenuTheme.BONE, 1.0)

		2:
			# Frame 2: Tamper seal severed and peeling back; cross-scratches abliterate stencil
			var half_w: float = seal_w * 0.42
			# Left tab peeling left
			draw_rect(Rect2(seal_x, seal_y, half_w, seal_h), UNION_RED)
			draw_line(Vector2(seal_x + half_w - 2, seal_y), Vector2(seal_x + half_w + 1, seal_y + 4), MenuTheme.BORDER, 1.0)
			# Right tab peeling right
			var r_tab_x: float = seal_x + seal_w - half_w
			draw_rect(Rect2(r_tab_x + 4, seal_y, half_w - 4, seal_h), UNION_RED)
			draw_line(Vector2(r_tab_x + 3, seal_y + seal_h), Vector2(r_tab_x + 6, seal_y + 5), MenuTheme.BORDER, 1.0)
			# Scarred gap between tabs
			draw_line(Vector2(seal_x + half_w, seal_y + 2), Vector2(r_tab_x + 4, seal_y + seal_h - 2), MenuTheme.BORDER, 1.0)
			draw_line(Vector2(seal_x + half_w + 2, seal_y + seal_h - 3), Vector2(r_tab_x + 2, seal_y + 3), MenuTheme.EDGE, 1.0)
			# Scratched out stencil
			draw_line(Vector2(14, 4), Vector2(40, 8), MenuTheme.EDGE, 1.0)
			draw_line(Vector2(16, 8), Vector2(38, 3), MenuTheme.BORDER, 1.0)

		3:
			# Frame 3: Settled bare scarred metal; severed red remnants at outer rivets only
			# Tiny torn seal corners near the right rivet
			draw_rect(Rect2(seal_x + seal_w - 8, seal_y + 1, 6, 4), UNION_RED)
			draw_rect(Rect2(seal_x + seal_w - 7, seal_y + 2, 4, 2), MenuTheme.INK)
			# Scarred gunmetal scratches across the plate
			draw_line(Vector2(seal_x - 12, seal_y + 4), Vector2(seal_x + 24, seal_y + 7), MenuTheme.EDGE, 1.0)
			draw_line(Vector2(seal_x + 8, seal_y + 8), Vector2(seal_x + 48, seal_y + 3), MenuTheme.BORDER, 1.0)
			draw_line(Vector2(20, seal_y + 5), Vector2(52, seal_y + 7), MenuTheme.EDGE, 1.0)
			draw_line(Vector2(32, seal_y + 8), Vector2(48, seal_y + 4), MenuTheme.BORDER, 1.0)

func _draw_union_sequence(rect: Rect2) -> void:
	var seal_w: float = minf(72.0, rect.size.x * 0.3)
	var seal_h: float = 10.0
	var seal_x: float = rect.size.x - seal_w - 12.0
	var seal_y: float = 3.0

	match current_frame:
		0:
			# Frame 0: Bare unsealed plate
			pass

		1:
			# Frame 1: Stencil registration mark aligns
			draw_rect(Rect2(seal_x + 8, seal_y + 3, 36, 2), MenuTheme.MUTED)
			draw_rect(Rect2(seal_x + 48, seal_y + 3, 16, 2), MenuTheme.MUTED)

		2:
			# Frame 2: Tamper seal descending / pressing down
			draw_rect(Rect2(seal_x, seal_y - 2, seal_w, seal_h - 2), UNION_RED)
			for i: int in range(4):
				var hx: float = seal_x + 8.0 + float(i) * 14.0
				draw_line(Vector2(hx, seal_y), Vector2(hx + 3, seal_y + seal_h - 4), MenuTheme.INK, 1.0)

		3:
			# Frame 3: Tamper seal firmly affixed with inspection mark ticking in
			draw_rect(Rect2(seal_x, seal_y, seal_w, seal_h), UNION_RED)
			for i: int in range(4):
				var hx: float = seal_x + 8.0 + float(i) * 14.0
				draw_line(Vector2(hx, seal_y + 2), Vector2(hx + 4, seal_y + seal_h - 2), MenuTheme.INK, 1.0)
			# Inspection checkmark in Bone
			var ck_x: float = seal_x + seal_w - 14.0
			draw_line(Vector2(ck_x, seal_y + 5), Vector2(ck_x + 3, seal_y + 8), MenuTheme.BONE, 2.0)
			draw_line(Vector2(ck_x + 3, seal_y + 8), Vector2(ck_x + 8, seal_y + 2), MenuTheme.BONE, 2.0)
