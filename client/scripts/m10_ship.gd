class_name M10Ship
extends Node3D

## Current ship occupants come from accepted mission facts. The reusable strips
## remain provisional casting, never proof of a named face or historical rescue.
const TINTS: Dictionary[String, Color] = {"tern": Color("cfc4a5"), "berth_crew_a": Color("a7bbad"), "berth_crew_b": Color("c6a880"), "edda": Color("b8c5c7"), "splice": Color("b6abbe")}
var _geometry: Dictionary = {}
var _figures: Dictionary[String, Sprite3D] = {}
var state_applied: int = 0

func clear_map() -> void:
	_geometry.clear()
	state_applied = 0
	for figure: Sprite3D in _figures.values():
		remove_child(figure)
		figure.queue_free()
	_figures.clear()

func configure_map(info: Dictionary) -> void:
	clear_map()
	if info.get("m10") is Dictionary and MissionState.map_error(info).is_empty():
		_geometry = MissionState.geometry_for(info)

func apply_state(state: Dictionary) -> void:
	if _geometry.is_empty() or state.get("id") != MissionState.M10_ID or not MissionState.validation_error({"tick": EquipmentState.MAX_EXACT_INTEGER, "state": state}, _geometry).is_empty():
		return
	state_applied += 1
	var facts: Dictionary = state["m10"]
	var people: Array[Dictionary] = [{"id": "tern", "feet": facts["pilot"]}]
	for passenger: Dictionary in facts["passengers"]:
		people.append(passenger)
	var present: Array[String] = []
	for person: Dictionary in people:
		var id: String = str(person["id"])
		present.append(id)
		if not _figures.has(id):
			var figure: Sprite3D = Sprite3D.new()
			figure.name = "ShipOccupant_" + id
			figure.texture = load(PlayerBody.strip_path(PlayerBody.SYNTHETIC if id in ["tern", "splice"] else PlayerBody.HUMAN)) as Texture2D
			figure.hframes = PlayerBody.IDLE_FRAMES + PlayerBody.WALK_FRAMES
			figure.pixel_size = EnemyAnimation.VIEW_SIZE / EnemyAnimation.TILE
			figure.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
			figure.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			figure.layers = ArenaSky.ACTOR_LAYERS
			figure.modulate = TINTS[id]
			add_child(figure)
			_figures[id] = figure
		var feet: Array = person["feet"]
		_figures[id].position = Vector3(float(feet[0]), float(feet[1]) + EnemyAnimation.CENTRE_HEIGHT, float(feet[2]))
	for id: String in _figures.keys():
		if id not in present:
			var figure: Sprite3D = _figures[id]
			remove_child(figure)
			figure.queue_free()
			_figures.erase(id)
