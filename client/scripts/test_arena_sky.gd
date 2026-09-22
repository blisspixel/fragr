extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var recall: ArenaSky.Preset = ArenaSky.preset_for("Recall Notice: intake prototype")
	var scrap: ArenaSky.Preset = ArenaSky.preset_for("Arena Duel")
	var yard: ArenaSky.Preset = ArenaSky.preset_for("Compliance Yard")
	if recall.ambient_color == scrap.ambient_color or recall.ambient_energy <= scrap.ambient_energy:
		push_error("test_arena_sky: Recall Notice still uses the scrapyard fill")
		quit(1)
		return
	if yard.ambient_color == scrap.ambient_color:
		push_error("test_arena_sky: Compliance Yard lost its own sky")
		quit(1)
		return
	if recall.ambient_energy < 1.0:
		push_error("test_arena_sky: interior fill is still too dim to read a near wall")
		quit(1)
		return
	print("test_arena_sky: PASS recall uses facility fill and arenas keep their venues")
	quit(0)
