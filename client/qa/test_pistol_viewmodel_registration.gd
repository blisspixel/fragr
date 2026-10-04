extends "res://scripts/test_viewmodel.gd"

# Candidate-only registration. The selected Pistol still uses column 150.
# All inherited cut-off, alpha, walking, fire and aspect-ratio gates remain.
func _column(weapon_name: String) -> int:
	return 112 if weapon_name == "Tack" else super._column(weapon_name)
