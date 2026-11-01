class_name LookPreview
extends SubViewportContainer

## The profile menu's live preview: the chosen body in the chosen look and
## accent, on the actual live model, dressed as a sideless free fighter
## (personal accent on the tape and the wrist band). Presentation only.

const SIZE: Vector2i = Vector2i(220, 300)

var body: String = ""
var look: int = FighterLooks.AUTO
var accent: int = FighterLooks.AUTO
var view: SkinnedCharacter = null
var _viewport: SubViewport = null
var _stage: Node3D = null


func _init() -> void:
	name = "LookPreview"
	stretch = true
	custom_minimum_size = Vector2(SIZE)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_viewport = SubViewport.new()
	_viewport.name = "PreviewViewport"
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.size = SIZE
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_viewport)
	_stage = Node3D.new()
	_viewport.add_child(_stage)
	var world: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b8bcc0")
	environment.ambient_light_energy = 0.55
	world.environment = environment
	_stage.add_child(world)
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.light_color = Color("fff1dc")
	key.light_energy = 1.2
	key.rotation_degrees = Vector3(-30, -150, 0)
	_stage.add_child(key)
	var fill: DirectionalLight3D = DirectionalLight3D.new()
	fill.light_color = Color("c8d4e0")
	fill.light_energy = 0.35
	fill.rotation_degrees = Vector3(-10, 40, 0)
	_stage.add_child(fill)
	var camera: Camera3D = Camera3D.new()
	camera.fov = 32.0
	_stage.add_child(camera)
	camera.look_at_from_position(Vector3(0.0, 1.0, 4.2), Vector3(0.0, 0.92, 0.0), Vector3.UP)
	camera.current = true


## Show `next_body` in `next_look` (AUTO shows the body's own art) with
## `next_accent` (AUTO shows a neutral callsign colour on the tape only).
func show_look(next_body: String, next_look: int, next_accent: int) -> void:
	next_body = PlayerBody.preference(next_body)
	if view == null or next_body != body:
		if view != null:
			view.queue_free()
			view = null
		var candidate: SkinnedCharacter = SkinnedCharacter.new()
		if not candidate.configure(next_body):
			candidate.free()
			body = ""
			return
		view = candidate
		view.name = "PreviewBody"
		# Three quarters toward the camera, so tape and wrist band both show.
		view.rotation.y = deg_to_rad(28.0)
		_stage.add_child(view)
	body = next_body
	look = next_look if FighterLooks.valid_look(body, next_look) else FighterLooks.AUTO
	accent = next_accent if FighterLooks.valid_accent(next_accent) else FighterLooks.AUTO
	FighterLooks.wear(view, FighterLooks.texture(body, look))
	var personal: Color = FighterLooks.accent_color(accent)
	var tape: Color = personal if personal.a > 0.0 else FactionPalette.callsign_color("preview")
	view.dress("free", tape)
	FighterLooks.mark(view, personal, false, 0)
	view.pose(0.0, false, true, false)
