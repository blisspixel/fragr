extends SceneTree
const TOUR = preload("res://scripts/qa_tour.gd")
var failures: int = 0
func _check(value: bool,message: String) -> void:
	if not value:
		failures += 1
		push_error("test_qa_m12: " + message)
func _initialize() -> void:
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://qa/m12_terms_of_cooperation.json"))
	_check(manifest is Dictionary and TOUR.valid_walks(manifest.get("states")) and TOUR.valid_combat_travel(manifest),"canonical route retains strict ordinary input and expectation validation")
	_check(TOUR.valid_m12_expectations({}),"other captures remain unchanged")
	_check(TOUR.valid_m12_expectations({"expect_m12_completed":["market_secured","arc_found"],"expect_m12_shelter_opened":false,"expect_m12_workers_released":true,"expect_m12_pump_health":[100,0],"expect_m12_assessor_wreck_union_kills":1,"expect_m12_aid_count":2}),"strict exact facts are accepted")
	for patch: Dictionary in [{"expect_m12_completed":["arc_found"]},{"expect_m12_completed":true},{"expect_m12_shelter_opened":1},{"expect_m12_workers_released":"true"},{"expect_m12_pump_health":[100]},{"expect_m12_pump_health":[100,101]},{"expect_m12_pump_health":[100,0.5]},{"expect_m12_assessor_wreck_union_kills":4},{"expect_m12_aid_count":1},{"expect_m12_aid_count":2.5}]:
		_check(not TOUR.valid_m12_expectations(patch),"malformed expectation cannot weaken capture proof: " + str(patch))
	if failures == 0:
		print("test_qa_m12: PASS ordered facts, real aid identities, pump bounds and optional receipt types")
	quit(0 if failures == 0 else 1)
