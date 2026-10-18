extends Control
class_name MenuBackdrop

var theme_context: MenuTheme.Context = MenuTheme.Context.FRONT_END

var content_width: float = 780.0:
	set(value):
		content_width = value
		queue_redraw()

## Fixed-seed industrial plates and a distant city, drawn in a low-resolution
## coordinate space. Native geometry keeps the menu crisp at any window size.
var _palette: Dictionary = MenuTheme.colors(MenuTheme.Context.FRONT_END)

func _ready() -> void:
	_palette = MenuTheme.colors(theme_context)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, size / Vector2(1280, 720))
	draw_rect(Rect2(0, 0, 1280, 720), _palette.ink)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 6767
	for y in range(0, 720, 48):
		for x in range(0, 1280, 64):
			var shade: float = rng.randf_range(0.07, 0.13)
			draw_rect(Rect2(x + 1, y + 1, 62, 46), _palette.ink.lerp(_palette.surface, (shade - 0.07) * 10.0))
	# Rust-lit horizon behind the machine ribs.
	for i in range(14):
		var x: float = float(i * 100 - 35)
		var height: float = rng.randf_range(90, 270)
		draw_rect(Rect2(x, 620 - height, 75, height), _palette.inset)
		for light in range(3):
			draw_rect(Rect2(x + 12 + light * 20, 640 - height, 6, 7), _palette.accent)
	for side in [0.0, 1056.0]:
		draw_colored_polygon(PackedVector2Array([
			Vector2(side, 0), Vector2(side + 224, 0), Vector2(side + 186, 150),
			Vector2(side + 186, 570), Vector2(side + 224, 720), Vector2(side, 720),
		]), _palette.surface)
		for rib in range(6):
			var y: float = float(80 + rib * 105)
			draw_rect(Rect2(side + 20, y, 144, 18), _palette.ink)
			draw_line(Vector2(side + 20, y), Vector2(side + 164, y), _palette.border, 3)
		for bolt_y in [28.0, 692.0]:
			for bolt_x in [25.0, 157.0]:
				draw_circle(Vector2(side + bolt_x, bolt_y), 7, _palette.ink)
				draw_line(Vector2(side + bolt_x - 3, bolt_y), Vector2(side + bolt_x + 3, bolt_y), _palette.muted, 2)
	var cabinet_width: float = maxf(720.0, content_width * (1280.0 / 1920.0) + 64.0)
	var cabinet_left: float = (1280.0 - cabinet_width) * 0.5
	draw_rect(Rect2(cabinet_left, 30, cabinet_width, 660), _palette.ink)
	draw_rect(Rect2(cabinet_left + 8, 38, cabinet_width - 16, 644), _palette.surface, false, 3)
	for x in range(0, 1280, 48):
		draw_colored_polygon(PackedVector2Array([
			Vector2(x, 0), Vector2(x + 24, 0), Vector2(x + 8, 14), Vector2(x - 16, 14)
		]), _palette.rust)
		draw_colored_polygon(PackedVector2Array([
			Vector2(x, 720), Vector2(x + 24, 720), Vector2(x + 40, 706), Vector2(x + 16, 706)
		]), _palette.rust)
	for i in range(160):
		var point: Vector2 = Vector2(rng.randf_range(0, 1280), rng.randf_range(0, 720))
		draw_line(point, point + Vector2(rng.randf_range(1, 6), 0), MenuTheme.alpha(_palette.accent, 0.08), 1)
