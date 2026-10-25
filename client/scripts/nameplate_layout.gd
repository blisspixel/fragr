class_name NameplateLayout
extends RefCounted

## A watched fighter's nameplate: the callsign in Silkscreen with the true
## behaviour chip and the score chip, over a pixel health bar. The words and
## the bar draw over the world, never cut by it: a plate whose centre the
## map's solids hide is hidden whole (`hidden_by`), so a deck edge can no
## longer bite a callsign in half ("NT LINDA"). Presentation only.

## The bar in cells: an ink rim round two rows of health over one of armour.
const BAR_CELLS: Vector2i = Vector2i(42, 6)
## Metres per cell at plate scale 1; the plate's own scale carries it.
const BAR_PIXEL: float = 0.055
## How far under the words' centre the bar sits, in metres at scale 1.
const BAR_DROP: float = 0.42
const BAR_INK: Color = Color("0a0a0c")
## Spent cells: dark steel, so the bar's length reads at a glance.
const BAR_EMPTY: Color = Color("2c2d32")
const BAR_HEALTH: Color = Color("e8e2d6")
## Half health and under. Never red: red light is the Union's attack tell.
const BAR_HURT: Color = Color("dc8c3c")
const BAR_ARMOR: Color = Color("8c847a")
## Armour the Custody Plate stacked past the ordinary cap.
const BAR_PLATED: Color = Color("ffd147")
const HEALTH_FULL: int = 100
const ARMOR_FULL: int = 100
## Plates draw after the world, after flag cloth and pickup tags.
const PLATE_PRIORITY: int = 10

## The plate's words: callsign, the server's true behaviour chip and the
## score chip. Health is the bar, not text.
static func plate_text(player_name: String, behavior: String, score_chip: String = "") -> String:
	return player_name + StanceChip.bracket(behavior) + score_chip

## World text that is never depth-cut: the words, the bar and any edge drawn
## on the plate draw over geometry. Cover is decided whole, by `hidden_by`.
static func style_plate(label: Label3D) -> void:
	if label == null:
		return
	label.no_depth_test = true
	label.render_priority = PLATE_PRIORITY
	label.outline_render_priority = PLATE_PRIORITY - 1
	label.double_sided = true
	for child: Node in label.get_children():
		if child is SpriteBase3D:
			(child as SpriteBase3D).no_depth_test = true
			(child as SpriteBase3D).render_priority = PLATE_PRIORITY

## The plate's health bar, made once under the label.
static func vitals_bar(label: Label3D) -> Sprite3D:
	var bar: Sprite3D = label.get_node_or_null("VitalsBar") as Sprite3D
	if bar != null:
		return bar
	bar = Sprite3D.new()
	bar.name = "VitalsBar"
	bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bar.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	bar.shaded = false
	bar.pixel_size = BAR_PIXEL
	bar.position = Vector3(0, -BAR_DROP, 0)
	bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bar.no_depth_test = true
	bar.render_priority = PLATE_PRIORITY
	var image: Image = Image.create(BAR_CELLS.x, BAR_CELLS.y, false, Image.FORMAT_RGBA8)
	bar.texture = ImageTexture.create_from_image(image)
	label.add_child(bar)
	return bar

## Health and armour as filled cells, for `paint_vitals` and the harnesses.
## A sliver of health always shows while the fighter lives.
static func vitals_cells(hp: int, armor: int) -> Vector3i:
	var inner: int = BAR_CELLS.x - 2
	var health: int = clampi(roundi(float(clampi(hp, 0, HEALTH_FULL)) / HEALTH_FULL * inner), 1 if hp > 0 else 0, inner)
	var plain: int = clampi(roundi(float(clampi(armor, 0, ARMOR_FULL)) / ARMOR_FULL * inner), 0, inner)
	var plated: int = clampi(roundi(float(maxi(armor - ARMOR_FULL, 0)) / ARMOR_FULL * inner), 0, inner)
	return Vector3i(health, plain, plated)

## The bar's cells as an image: ink rim, two rows of health, a spacer, one
## row of armour with any plated armour laid over it from the left.
static func vitals_image(hp: int, armor: int) -> Image:
	var cells: Vector3i = vitals_cells(hp, armor)
	var inner: int = BAR_CELLS.x - 2
	var image: Image = Image.create(BAR_CELLS.x, BAR_CELLS.y, false, Image.FORMAT_RGBA8)
	image.fill(BAR_INK)
	image.fill_rect(Rect2i(1, 1, inner, 2), BAR_EMPTY)
	image.fill_rect(Rect2i(1, 4, inner, 1), BAR_EMPTY)
	image.fill_rect(Rect2i(1, 1, cells.x, 2), BAR_HEALTH if hp > HEALTH_FULL / 2 else BAR_HURT)
	image.fill_rect(Rect2i(1, 4, cells.y, 1), BAR_ARMOR)
	image.fill_rect(Rect2i(1, 4, cells.z, 1), BAR_PLATED)
	return image

static func paint_vitals(bar: Sprite3D, hp: int, armor: int) -> void:
	if bar == null:
		return
	var key: Vector2i = Vector2i(hp, armor)
	if bar.get_meta("vitals", Vector2i(-1, -1)) == key:
		return
	bar.set_meta("vitals", key)
	var image: Image = vitals_image(hp, armor)
	var texture: ImageTexture = bar.texture as ImageTexture
	if texture != null and texture.get_size() == Vector2(BAR_CELLS):
		texture.update(image)
	else:
		bar.texture = ImageTexture.create_from_image(image)

## Keep the most useful readable nameplate when projected labels overlap.
## Entries have id, screen rect, priority (lower wins), and camera distance.
## Reserved rects, such as a flag cloth, are already occupied.
static func choose(entries: Array[Dictionary], reserved: Array = []) -> Array[String]:
	var ordered: Array[Dictionary] = entries.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["priority"]) != int(b["priority"]):
			return int(a["priority"]) < int(b["priority"])
		var a_distance_cm: int = roundi(float(a["distance"]) * 100.0)
		var b_distance_cm: int = roundi(float(b["distance"]) * 100.0)
		if a_distance_cm != b_distance_cm:
			return a_distance_cm < b_distance_cm
		return str(a["id"]) < str(b["id"])
	)
	var visible: Array[String] = []
	var occupied: Array[Rect2] = []
	for area: Variant in reserved:
		if area is Rect2 and (area as Rect2).size != Vector2.ZERO:
			occupied.append(area)
	for entry: Dictionary in ordered:
		var area: Rect2 = entry["rect"]
		var overlaps: bool = false
		for prior: Rect2 in occupied:
			if prior.intersects(area):
				overlaps = true
				break
		if not overlaps:
			visible.append(str(entry["id"]))
			occupied.append(area)
	return visible


## A plate nearer the eye than this would fill the view; it hides.
const NEAR_HIDE: float = 2.5

## True when a plate must not draw from this eye: the map's solids stand
## between them, or it sits so close its words would fill the screen. Plates
## draw over geometry, so cover decides a plate whole, never in part.
static func hidden_by(eye: Vector3, plate: Vector3, solids: Array) -> bool:
	if eye.distance_to(plate) < NEAR_HIDE:
		return true
	return not solids.is_empty() and not AimAssist.line_of_sight(eye, plate, solids)


## Screen rect of a billboard label, grown slightly so neighbors do not touch it.
static func project_label(view: Camera3D, label: Label3D) -> Rect2:
	var font: Font = label.font if label.font != null else ThemeDB.fallback_font
	var text_size: Vector2 = Vector2(label.text.length() * label.font_size * 0.6, label.font_size)
	if font != null:
		text_size = font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size)
	var width: float = (text_size.x + label.outline_size * 2.0 + 12.0) * label.pixel_size * label.scale.x
	var height: float = (text_size.y + label.outline_size + 8.0) * label.pixel_size * label.scale.y
	var area: Rect2 = project_span(view, label.global_position, width * 0.5, height * 0.5)
	# The bar under the words is part of the plate: two plates whose bars
	# would touch are an overlap too.
	var bar: Sprite3D = label.get_node_or_null("VitalsBar") as Sprite3D
	if bar != null and bar.visible and area.has_area():
		var scale: float = label.scale.x
		var bar_area: Rect2 = project_span(view, bar.global_position,
			BAR_CELLS.x * BAR_PIXEL * scale * 0.5, BAR_CELLS.y * BAR_PIXEL * scale * 0.5)
		if bar_area.has_area():
			area = area.merge(bar_area.grow(2.0))
	return area


## Screen-aligned span around a world point. An empty rect means the point is behind the camera.
static func project_span(view: Camera3D, world_center: Vector3, half_width: float, half_height: float) -> Rect2:
	if view == null or view.is_position_behind(world_center) or half_width <= 0.0 or half_height <= 0.0:
		return Rect2()
	var right: Vector3 = view.global_transform.basis.x.normalized()
	var up: Vector3 = view.global_transform.basis.y.normalized()
	var left_px: Vector2 = view.unproject_position(world_center - right * half_width)
	var right_px: Vector2 = view.unproject_position(world_center + right * half_width)
	var top_px: Vector2 = view.unproject_position(world_center + up * half_height)
	var bottom_px: Vector2 = view.unproject_position(world_center - up * half_height)
	return Rect2(Vector2(minf(left_px.x, right_px.x), minf(top_px.y, bottom_px.y)),
		Vector2(absf(right_px.x - left_px.x), absf(bottom_px.y - top_px.y))).grow(4.0)
