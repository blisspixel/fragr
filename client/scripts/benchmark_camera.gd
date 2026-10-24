extends RefCounted
class_name BenchmarkCamera

## Larak Lot orbit, just inside the wall bands and above the Roof, so the
## whole car park, its landmarks and its lights stay in frame. The pose is a
## function of scene time in seconds, so two machines that reach the same
## timestamp aim at the same place. Stepping the angle once per frame would
## make a fast machine walk a different path. Scene revision 2: revision 1
## circled the retired Arena Duel field at 46 m, 12 m up; its scores are not
## comparable with these.

const SCENE_REVISION: int = 2
const RADIUS: float = 31.0
const HEIGHT: float = 17.0
const ORBIT_SECONDS: float = 20.0
const LOOK: Vector3 = Vector3(0.0, 1.5, 0.0)

static func pose(elapsed_s: float) -> Dictionary:
	var turns: float = elapsed_s / ORBIT_SECONDS
	var angle: float = TAU * turns
	return {
		"position": Vector3(cos(angle) * RADIUS, HEIGHT, sin(angle) * RADIUS),
		"look": LOOK,
	}

static func apply(camera: Node3D, elapsed_s: float) -> void:
	var sample: Dictionary = pose(elapsed_s)
	var position: Vector3 = sample["position"]
	camera.global_position = position
	var look: Vector3 = sample["look"]
	if position.distance_squared_to(look) > 0.01:
		camera.look_at(look, Vector3.UP)
