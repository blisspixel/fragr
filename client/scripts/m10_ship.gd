class_name M10Ship
extends Node3D

## Current ship occupants come from accepted mission facts. Tern and Edda share
## their named berth skins; other retained strips remain provisional casting.
const TINTS: Dictionary[String, Color] = {"tern": Color("cfc4a5"), "berth_crew_a": Color("a7bbad"), "berth_crew_b": Color("c6a880"), "edda": Color("b8c5c7"), "splice": Color("b6abbe")}
var _geometry: Dictionary = {}
var _figures: Dictionary[String, CivilianFigure] = {}
var state_applied: int = 0
## The ship's golden-slice dressing. It outlives a re-sent MapInfo for the
## same layout, clears itself for any other map and leaves with the map.
var dressing: M10Dressing

func clear_map() -> void:
	_clear_occupants()
	_drop_dressing()

func _drop_dressing() -> void:
	if dressing != null:
		remove_child(dressing)
		dressing.queue_free()
		dressing = null

func _clear_occupants() -> void:
	_geometry.clear()
	state_applied = 0
	for figure: CivilianFigure in _figures.values():
		remove_child(figure)
		figure.queue_free()
	_figures.clear()

func configure_map(info: Dictionary) -> void:
	_clear_occupants()
	# Off-map, a refused map or another layout gets no dressing at all.
	if not info.get("m10") is Dictionary or not MissionState.map_error(info).is_empty():
		_drop_dressing()
		return
	if not M10Dressing.ship_layout(info):
		_drop_dressing()
	else:
		if dressing == null:
			dressing = M10Dressing.new()
			dressing.name = "ShipDressing"
			add_child(dressing)
		dressing.configure_map(info)
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
			var figure: CivilianFigure = CivilianFigure.new()
			figure.name = "ShipOccupant_" + id
			figure.configure(id, TINTS[id])
			# The current pilot stands at the fore-facing command console. This
			# is venue presentation, not an authoritative steering direction.
			if id == "tern":
				figure.rotation.y = PI
			add_child(figure)
			_figures[id] = figure
		var feet: Array = person["feet"]
		_figures[id].place_feet(Vector3(float(feet[0]), float(feet[1]), float(feet[2])))
	for id: String in _figures.keys():
		if id not in present:
			var figure: CivilianFigure = _figures[id]
			remove_child(figure)
			figure.queue_free()
			_figures.erase(id)
