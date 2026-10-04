extends "res://scripts/qa_tour.gd"

## Keep the ordinary route as the source of truth and add three art views.
const ART_STOPS: Dictionary[String, Dictionary] = {
	"clinic_recovery": {"name": "maintained_care_counter", "camera": "first_person", "combat_travel": false,
		"walk_to": [[-30, 0, 2], [-29, 0, 2], [-29, 0, 10.5]], "look_at": [-28.5, 1.0, 12.25],
		"note": "Ordinary movement inspects the maintained care station, without entering a patient route."},
	"repair_bench_supplies": {"name": "shared_charging_bench", "camera": "first_person", "look_at": [-9, 0.9, 10.75],
		"note": "Shaped cable spools, shared dock, contact tray and repair iron sit on the authoritative bench."},
	"meal_table_secret": {"name": "interrupted_shared_meal", "camera": "first_person", "look_at": [-0.8, 1.0, 28.5],
		"note": "Individual ceramic cups and bowls, bread and utensils give the retained table a civilian use."},
}

func _load_manifest() -> Dictionary:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://qa/m04-market.json"))
	if not raw is Dictionary or not valid_walks(raw.get("states")) or not valid_combat_travel(raw):
		push_error("m04_lived_detail_tour: ordinary M04 route is invalid")
		return {}
	var tour: Dictionary = raw
	var expanded: Array[Dictionary] = []
	var inserted: int = 0
	for stage: Dictionary in tour["states"]:
		expanded.append(stage)
		if ART_STOPS.has(stage.get("name", "")):
			expanded.append(ART_STOPS[stage["name"]].duplicate(true))
			inserted += 1
	if inserted != ART_STOPS.size() or not valid_walks(expanded):
		push_error("m04_lived_detail_tour: art views no longer match the ordinary route")
		return {}
	tour["states"] = expanded
	return tour
