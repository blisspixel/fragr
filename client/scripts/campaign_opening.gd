class_name CampaignOpening
extends ScenePlayer

## The M01 opening: the `opening` scene manifest on the shared scene player.
## Reader-paced until narration exists. Completion is a request, never mission
## authority; GameManager owns the readiness handoff.

const SCENE_ID: String = "opening"
const BEATS: Array[String] = ["HOME", "CHOICE", "ADDRESS", "RECALL", "PURSUIT"]

func _init() -> void:
	var manifest: Dictionary = StoryScene.load_scene(SCENE_ID)
	scene = manifest if not manifest.is_empty() else fallback()

## Plain keyed pages, the opening as it shipped before manifests. Used only when
## the manifest cannot load, so a broken file never blocks the campaign.
static func fallback() -> Dictionary:
	var pages: Array = []
	for beat: String in BEATS:
		pages.append({
			"id": beat,
			"title_key": "STORY_M01_" + beat + "_TITLE",
			"caption_key": "STORY_M01_" + beat + "_BODY",
		})
	return {"format": float(StoryScene.FORMAT), "id": SCENE_ID, "title_key": "MISSION_M01_TITLE", "skip_key": "STORY_SKIP", "shots": pages}
