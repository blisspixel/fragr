extends SceneTree

## Checks the Proximity Mine's art contract for Level 8: the pickup resolves
## by its wire kind, the face-on device has one canvas for every lamp state,
## the states differ only at the lamp, each wire phase picks the right state,
## and the first-person frames share the grenade hand's canvas.

var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("test_mine_art: " + message)

func _run() -> void:
	var pickup: Texture2D = WeaponArt.pickup_texture("proximity_mine", "", "")
	_check(pickup != null and pickup == WeaponArt.SUPPLY["proximity_mine"], "the mine pickup resolves by its wire kind")
	_check(pickup.get_height() < WeaponArt.SUPPLY["health"].get_height(), "a mine is drawn smaller than a medkit pickup")
	var dark: Image = WeaponArt.MINE_DEVICE["dark"].get_image()
	var changed: Rect2i = Rect2i()
	for state: String in ["arming", "live"]:
		var image: Image = WeaponArt.MINE_DEVICE[state].get_image()
		_check(image.get_size() == dark.get_size(), state + " shares the device canvas")
		var differing: int = 0
		for y: int in range(image.get_height()):
			for x: int in range(image.get_width()):
				if image.get_pixel(x, y) != dark.get_pixel(x, y):
					differing += 1
					changed = Rect2i(x, y, 1, 1) if changed.size == Vector2i.ZERO else changed.expand(Vector2i(x, y))
		_check(differing >= 9, state + " lights a lens a room can read")
	var centre: Vector2 = Vector2(dark.get_size()) * 0.5
	_check(changed.size.x <= 9 and changed.size.y <= 9 and (Vector2(changed.get_center()) - centre).length() < 4.0,
		"lamp states differ only at the centred lens: %s" % changed)
	_check(WeaponArt.mine_device("flying", false) == WeaponArt.MINE_DEVICE["dark"], "a mine in flight is dark")
	_check(WeaponArt.mine_device("arming", false) == WeaponArt.MINE_DEVICE["arming"], "arming is a steady amber lamp")
	_check(WeaponArt.mine_device("armed", true) == WeaponArt.MINE_DEVICE["live"]
		and WeaponArt.mine_device("armed", false) == WeaponArt.MINE_DEVICE["dark"], "an armed mine blinks red")
	_check(WeaponArt.mine_device("tripped", true) == WeaponArt.MINE_DEVICE["live"], "a tripped mine flashes red")
	for frame: Texture2D in [WeaponArt.MINE_READY, WeaponArt.MINE_PLACE]:
		_check(frame.get_size() == WeaponArt.GRENADE_READY.get_size(), "mine hand frames share the grenade hand's canvas")
	if failures == 0:
		print("test_mine_art: PASS pickup kind, device canvas, lens-only states, phase mapping, hand frames")
	quit(0 if failures == 0 else 1)
