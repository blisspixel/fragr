class_name RunFixture
extends RefCounted
## Shared facts for harnesses that hand the local child a saved campaign run.
## The server reads and writes exactly one run-file version and refuses every
## other one, so fixtures are always written in the current shape.

const VERSION: int = 24

## Every save is an atomic replace of run.json under run.lock. Nothing else,
## such as an archive, copy or temporary file, may remain afterwards.
static func only_live_run(directory: String) -> bool:
	var names: Array = Array(DirAccess.get_files_at(directory))
	names.sort()
	return names == ["run.json", "run.lock"]
