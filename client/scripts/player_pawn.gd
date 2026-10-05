extends Node3D

const StanceChipScript = preload("res://scripts/stance_chip.gd")

var player_id: String = ""
var player_name: String = ""
var hp: int = 100
var player_color: Color = Color.WHITE
var hit_flash_timer: float = 0.0
var idle_anim_timer: float = 0.0
var current_weapon: String = ""
var behavior: String = ""
var is_highlighted: bool = false
var is_local_fp: bool = false
var armor: int = 0
var nameplate_enabled: bool = true
var is_campaign_enemy: bool = false
var is_campaign_companion: bool = false
## Side in a team mode ("union" or "coalition"), empty otherwise.
var team: String = ""
## Holds the golden Railgun.
var golden: bool = false
## The callsign colour before a side took it over.
var _own_color: Color = Color.WHITE
## The server-accepted body this pawn wears, or empty for an actor without
## one (Union actors, the arena boss, an older server's fighters).
var body_kind: String = ""
## Ground distance walked, which advances the body's gait.
var _walked: float = 0.0
var campaign_actor: Dictionary = {}
var _has_authoritative_state: bool = false
var enemy_view: EnemyView = null
var latch_view: LatchView = null
var _notary_shadow: MeshInstance3D = null
## Scope glint of a Ranged Sweeper, shown only during its server windup.
var marksman_tell: RangedSweeperTell = null

var target_position: Vector3 = Vector3.ZERO
var prediction_active: bool = false
var predicted_position: Vector3 = Vector3.ZERO
var predicted_speed: float = 0.0
var presentation_speed: float = 0.0
var target_yaw: float = 0.0
var target_pitch: float = 0.0
var presentation_yaw: float = 0.0
var presentation_pitch: float = 0.0
var remote_presentation: RemotePresentation = RemotePresentation.new()
const INTERP_SPEED: float = 10.0

# Far-cam billboard scale: follow sits ~12m; tip overview ~36m.
# Below REF, scale stays 1 so close follow is unchanged. Beyond REF, scale grows with
# distance / REF (capped) so far spectators still read Cyanex/Kragge silhouettes.
const FAR_CAM_REF_DIST: float = 12.0
const FAR_CAM_MAX_SCALE: float = 3.5
## Below this distance a nameplate shrinks with the distance, so its size on
## screen stops growing. A Label3D has a fixed size in the world, which means a
## fighter two metres away wears a name tall enough to hide the room behind it.
const NAMEPLATE_NEAR_DIST: float = 9.0
## How small a close nameplate may get, so it does not vanish at point blank.
const NAMEPLATE_MIN_SCALE: float = 0.22
const HIT_SCALE_BOOST: float = 1.12

var _far_cam_scale: float = 1.0
## Distant silhouettes may be enlarged for a broadcast overview, never while
## aiming or watching through a fighter's eyes: that would misrepresent cover.
var broadcast_scale_enabled: bool = false

@onready var label: Label3D = $Label3D
@onready var highlight: MeshInstance3D = $Highlight
@onready var body: Sprite3D = $Body
@onready var weapon_sprite: Sprite3D = $Body/WeaponSprite
@onready var muzzle: Sprite3D = $Body/Muzzle
@onready var muzzle_glow: OmniLight3D = $Body/Muzzle/MuzzleGlow
@onready var fire_sound: AudioStreamPlayer3D = $FireSound
@onready var hit_sound: AudioStreamPlayer3D = $HitSound
@onready var cycle_sound: AudioStreamPlayer3D = get_node_or_null("CycleSound")
@onready var tell_sound: AudioStreamPlayer3D = get_node_or_null("TellSound")
@onready var down_sound: AudioStreamPlayer3D = get_node_or_null("DownSound")

## The Shotgun's pump cycles after each blast. Scatter's server cooldown is
## 12 ticks at 20 Hz, so the next shot can land 0.60 s after this one; the
## cue starts at 0.22 s and is shorter than 0.36 s, so the action always
## closes before the trigger can fire again. Presentation only: it never
## gates or delays a shot, and it is not a reload.
const SHOTGUN_CYCLE_PATH: String = "res://assets/audio/shotgun/cycle.wav"
const SHOTGUN_CYCLE_DELAY: float = 0.22
const SHOTGUN_COOLDOWN_SECONDS: float = 0.6
## Melee has its own swing; it must never fall back to a gunshot.
const MELEE_SWING_PATHS: Dictionary[String, String] = {
	"Fists": "res://assets/audio/melee/fists.wav",
	"Shiv": "res://assets/audio/melee/shiv.wav",
}
## Union telegraphs: `<kind>/tell.wav`, keyed by the authoritative windup.
const TELL_PATH: String = "res://assets/audio/%s/tell.wav"
## Charge-shaped tells are stretched to the actual windup so they peak at the shot.
const STRETCHED_TELLS: Array[String] = ["turret"]
## Kinds whose tell has its own long-range presenter (RangedSweeperAudio).
const DEDICATED_TELLS: Array[String] = ["ranged_sweeper"]
const TELL_PITCH_MIN: float = 0.8
const TELL_PITCH_MAX: float = 1.25
const DOWN_BODY_PATH: String = "res://assets/audio/down/body.wav"
const DOWN_ROBOT_PATH: String = "res://assets/audio/down/robot.wav"
## Union machines fall as machines; the Notary keeps its own crash.
const ROBOT_KINDS: Array[String] = ["sweeper", "heavy_sweeper", "turret", "crawler", "jammer"]

var muzzle_flash_texture: Texture2D
var rail_beam_texture: Texture2D

var weapon_textures = {}
const HELD_PROFILE_SCALE: float = 32.0 / 80.0
## The scene's pixel size for a 32 pixel weapon icon.
var weapon_pixel_size: float = 0.026
var cyanex_texture: Texture2D
var kragge_texture: Texture2D

# Art bible muted brand tints (bone/gunmetal/rust/blood/ember + muted cyan/magenta).
# Keep silhouettes readable: labels carry brand color; body stays near-white multiply.
const BOT_COLORS = {
	"Dead Air Dan": Color(0.75, 0.28, 0.22),
	"Nightfall": Color(0.35, 0.58, 0.62),
	"Static Kid": Color(0.82, 0.55, 0.22),
	"Aunt Linda": Color(0.55, 0.48, 0.4),
	"Scout Ant": Color(0.62, 0.32, 0.42),
	"Crackpot": Color(0.45, 0.38, 0.5),
	"Buzzkill": Color(0.769, 0.4, 0.18),
	"Tin Foil Tina": Color(0.4, 0.62, 0.64),
	"COMPLIANCE-DRONE": Color(0.55, 0.72, 0.35),
	"AUDITOR": Color(0.72, 0.78, 0.28),
	"NODS-01": Color(0.45, 0.48, 0.42),
	"NODS-02": Color(0.42, 0.45, 0.4),
	"NODS-03": Color(0.48, 0.5, 0.44),
	"NODS-04": Color(0.4, 0.43, 0.38),
	"NODS-05": Color(0.46, 0.49, 0.41),
	"NODS-06": Color(0.43, 0.46, 0.39),
	"NODS-07": Color(0.47, 0.5, 0.43),
	"NODS-08": Color(0.41, 0.44, 0.37)
}


# Hangar Candy / Kragge grit vs Cyanex / Night Watch signal.
const KRAGGE_BOTS = ["Dead Air Dan", "Aunt Linda", "Buzzkill"]
const CYANEX_BOTS = ["Nightfall", "Static Kid", "Scout Ant", "Crackpot", "Tin Foil Tina"]

func _ready():
	if label:
		label.text = player_name
	if muzzle:
		muzzle.visible = false
	if muzzle_glow:
		muzzle_glow.light_energy = 0.0
	if highlight:
		highlight.visible = false
	
	_load_audio_streams()
	
	muzzle_flash_texture = load("res://assets/vfx/32/muzzle_flash.png")
	rail_beam_texture = load("res://assets/vfx/32/rail_beam_tip.png")
	
	for weapon: String in WeaponArt.PROFILE:
		weapon_textures[weapon] = WeaponArt.PROFILE[weapon]
	if weapon_sprite:
		weapon_pixel_size = weapon_sprite.pixel_size
	
	cyanex_texture = load("res://assets/characters/64/cyanex_idle_strip.png")
	kragge_texture = load("res://assets/characters/64/kragge_idle_strip.png")

var fire_streams = {}
var hit_streams = {}
## The impact sound used when the shooter's weapon is not known.
var generic_hit_stream: AudioStream = null
var melee_streams: Dictionary[String, AudioStream] = {}
var tell_streams: Dictionary[String, AudioStream] = {}
var down_body_stream: AudioStream = null
var down_robot_stream: AudioStream = null
## The Ranged Sweeper fires its own machine-mounted shot, not the player's rifle.
var ranged_fire_stream: AudioStream = null
## One-shot timer owned by the pawn, so a freed fighter never pumps late.
var _cycle_timer: Timer = null
## The windup this pawn last announced, as its authoritative start tick.
var _tell_started: int = -1
## Cues actually started, for presentation checks.
var cycle_count: int = 0
var tell_count: int = 0
var down_count: int = 0
var impact_count: int = 0

func _load_audio_streams():
	var audio_dir = "res://assets/audio/"
	var fallback_fire = audio_dir + "fire.wav"
	var fallback_hit = audio_dir + "hit.wav"
	
	for w in ["Tack", "Flechette", "Rail", "Scatter"]:
		var key = w.to_lower()
		var fire_path = audio_dir + "fire_" + key + ".wav"
		var hit_path = audio_dir + "hit_" + key + ".wav"
		if ResourceLoader.exists(fire_path):
			fire_streams[w] = load(fire_path)
		elif ResourceLoader.exists(fallback_fire):
			fire_streams[w] = load(fallback_fire)
		if ResourceLoader.exists(hit_path):
			hit_streams[w] = load(hit_path)
		elif ResourceLoader.exists(fallback_hit):
			hit_streams[w] = load(fallback_hit)
	
	# The Sniper Rifle's sounds come from the level 7 table, not a file name.
	if ResourceLoader.exists(L07Assets.SNIPER_FIRE_SOUND):
		fire_streams["Sniper"] = load(L07Assets.SNIPER_FIRE_SOUND)
	if ResourceLoader.exists(L07Assets.SNIPER_HIT_SOUND):
		hit_streams["Sniper"] = load(L07Assets.SNIPER_HIT_SOUND)
	if fire_sound and ResourceLoader.exists(fallback_fire):
		fire_sound.stream = load(fallback_fire)
	if ResourceLoader.exists(fallback_hit):
		generic_hit_stream = load(fallback_hit)
	if hit_sound and ResourceLoader.exists(fallback_hit):
		hit_sound.stream = load(fallback_hit)
	if cycle_sound and ResourceLoader.exists(SHOTGUN_CYCLE_PATH):
		cycle_sound.stream = load(SHOTGUN_CYCLE_PATH)
	if cycle_sound and _cycle_timer == null:
		_cycle_timer = Timer.new()
		_cycle_timer.name = "ShotgunCycle"
		_cycle_timer.one_shot = true
		_cycle_timer.timeout.connect(_on_shotgun_cycle)
		add_child(_cycle_timer)
	for weapon: String in MELEE_SWING_PATHS:
		if ResourceLoader.exists(MELEE_SWING_PATHS[weapon]):
			melee_streams[weapon] = load(MELEE_SWING_PATHS[weapon])
	for kind: String in ActorState.KINDS:
		if kind in DEDICATED_TELLS:
			continue
		var tell_path: String = TELL_PATH % kind
		if ResourceLoader.exists(tell_path):
			tell_streams[kind] = load(tell_path)
	if ResourceLoader.exists(DOWN_BODY_PATH):
		down_body_stream = load(DOWN_BODY_PATH)
	if ResourceLoader.exists(DOWN_ROBOT_PATH):
		down_robot_stream = load(DOWN_ROBOT_PATH)
	if ResourceLoader.exists(L07Assets.RANGED_SWEEPER_FIRE_SOUND):
		ranged_fire_stream = load(L07Assets.RANGED_SWEEPER_FIRE_SOUND)

## Fraction of the remaining distance to close this frame.
##
## `speed * delta` is the obvious form and it is frame-rate dependent: at 240
## frames a second it closes 4 percent per frame and at 40 it closes 25, which
## are not the same curve, so two machines render a fighter in different places
## from identical snapshots. Above a delta of 1/speed it overshoots outright.
## The exponential form closes the same fraction per unit of *time* whatever
## the frame rate, which is what smoothing was always supposed to mean.
static func smoothing(speed: float, delta: float) -> float:
	return 1.0 - exp(-speed * delta)

func _process(delta: float) -> void:
	var t: float = smoothing(INTERP_SPEED, delta)
	var previous: Vector3 = position
	var rendered: Dictionary = remote_presentation.sample(Time.get_ticks_usec()) \
		if not prediction_active and not is_campaign_enemy and not is_campaign_companion else {}
	if prediction_active:
		position = predicted_position
		presentation_yaw = target_yaw
		presentation_pitch = target_pitch
	elif not rendered.is_empty():
		position = rendered["position"]
		presentation_yaw = float(rendered["yaw"])
		presentation_pitch = float(rendered["pitch"])
	else:
		position = position.lerp(target_position, t)
		presentation_yaw = lerp_angle(-rotation.y, target_yaw, t)
		presentation_pitch = lerpf(presentation_pitch, target_pitch, t)
	var travel: float = Vector2(position.x - previous.x, position.z - previous.z).length()
	# Motion feedback follows the rendered fighter, including observed agents.
	# Discontinuities and dead bodies are not walking strides.
	presentation_speed = predicted_speed if prediction_active and hp > 0 else (travel / delta if delta > 0.0 and travel < 2.0 and hp > 0 else 0.0)
	# The pawn's muzzle and weapon sprites hang off its local +X, so that is
	# what has to point where the server is sending it.
	rotation.y = ServerYaw.pawn_rotation_y(presentation_yaw)
	
	_update_far_cam_scale()
	
	if hit_flash_timer > 0:
		hit_flash_timer -= delta
		if hit_flash_timer <= 0 and body:
			_update_body_color(false)
	
	if enemy_view != null and body:
		enemy_view.advance(delta, travel)
		var camera: Camera3D = get_viewport().get_camera_3d()
		var to_camera: Vector3 = camera.global_position - global_position if camera else ServerYaw.forward(target_yaw)
		enemy_view.render(body, -rotation.y, to_camera)
		_update_notary_shadow()
		if marksman_tell != null:
			marksman_tell.present(campaign_actor, enemy_view.tick, enemy_view.elapsed)
	elif latch_view != null:
		latch_view.advance(delta, travel, str(campaign_actor.get("phase", "following")))
	else:
		idle_anim_timer += delta * 4.0
	if body and enemy_view == null and latch_view == null:
		if body_kind.is_empty():
			body.frame = int(idle_anim_timer) % 4
		else:
			_walked += travel
			body.frame = PlayerBody.frame(idle_anim_timer, _walked, presentation_speed)

func set_player_data(id: String, name: String):
	player_id = id
	player_name = name
	
	if BOT_COLORS.has(name):
		player_color = BOT_COLORS[name]
	elif str(name).begins_with("NODS-"):
		player_color = Color(0.44, 0.47, 0.4)
	elif name == "AUDITOR":
		player_color = Color(0.72, 0.78, 0.28)
	else:
		var color_val = float(abs(hash(id)) % 100) / 100.0
		player_color = Color.from_hsv(color_val, 0.8, 0.9)
	
	if KRAGGE_BOTS.has(name):
		body.texture = kragge_texture
	else:
		body.texture = cyanex_texture
	
	# Continuance drone: taller billboard silhouette vs scrap fighters.
	if str(name).begins_with("NODS-") and label:
		label.modulate = Color(0.7, 0.75, 0.65)
	if name == "AUDITOR" and body:
		body.scale = Vector3(1.25, 1.45, 1.25)
	if name == "COMPLIANCE-DRONE" and body:
		body.pixel_size = body.pixel_size * 1.35
	
	_own_color = player_color
	if label:
		label.text = name
		label.modulate = player_color
	
	target_position = position
	# target_yaw is in the server's convention, and rotation.y is not, so this
	# seeds from the identity facing rather than converting a rotation that has
	# not been set yet.
	target_yaw = 0.0

func update_state(state: Dictionary, snapshot_tick: int = 0):
	is_campaign_enemy = ActorState.is_union(state)
	is_campaign_companion = ActorState.is_companion(state)
	campaign_actor = state["campaign"] if is_campaign_enemy or is_campaign_companion else {}
	if is_campaign_enemy:
		if enemy_view == null:
			enemy_view = EnemyView.new()
			muzzle.position = Vector3(0.88, 0.52, -0.14)
			muzzle.pixel_size = 0.005
		enemy_view.update(state, snapshot_tick, body)
		if campaign_actor.get("kind") == "ranged_sweeper" and marksman_tell == null:
			marksman_tell = RangedSweeperTell.new()
			marksman_tell.name = "MarksmanTell"
			add_child(marksman_tell)
		if campaign_actor.get("kind") == "notary" and _notary_shadow == null:
			_notary_shadow = MeshInstance3D.new()
			_notary_shadow.name = "NotaryFloorShadow"
			var shadow_plane: PlaneMesh = PlaneMesh.new()
			shadow_plane.size = Vector2(1.6, 1.3)
			_notary_shadow.mesh = shadow_plane
			var shadow_material: ShaderMaterial = ShaderMaterial.new()
			shadow_material.shader = preload("res://assets/shaders/notary_shadow.gdshader")
			_notary_shadow.material_override = shadow_material
			_notary_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_notary_shadow.layers = ArenaSky.WORLD_LAYERS
			add_child(_notary_shadow)
		weapon_sprite.visible = false
	elif is_campaign_companion:
		if latch_view == null:
			latch_view = LatchView.new()
			latch_view.name = "LatchView"
			latch_view.position.y = -1.5
			# Shared ward geometry faces local +Z; a pawn faces local +X.
			latch_view.rotation.y = PI / 2.0
			add_child(latch_view)
			latch_view.set_render_layers(ArenaSky.ACTOR_LAYERS)
			latch_view.set_near_camera_clip(true)
			label.position.y = 0.68
		body.visible = false
		weapon_sprite.visible = false
		latch_view.set_weapon_visible(campaign_actor["phase"] != "releasing")
	target_position = Vector3(state.x, state.y, state.z)
	target_yaw = state.yaw
	target_pitch = clampf(float(state.get("pitch", 0.0)), -ServerYaw.PITCH_LIMIT, ServerYaw.PITCH_LIMIT)
	
	var old_hp = hp
	hp = state.hp
	armor = int(state.get("armor", 0))
	if not is_campaign_enemy and not is_campaign_companion and snapshot_tick > 0:
		if remote_presentation.accept(snapshot_tick, target_position, target_yaw,
				target_pitch, hp > 0, Time.get_ticks_usec()) and remote_presentation.discontinuity \
				and not prediction_active:
			position = target_position
			presentation_yaw = target_yaw
			presentation_pitch = target_pitch
			rotation.y = ServerYaw.pawn_rotation_y(presentation_yaw)
	
	if _has_authoritative_state and old_hp > hp and hp > 0:
		show_hit_feedback()
	elif _has_authoritative_state and old_hp > 0 and hp <= 0:
		_play_down()
	_has_authoritative_state = true
	_update_tell()
	
	if not is_campaign_enemy and not is_campaign_companion and PlayerBody.valid(state.get("body")) and state["body"] != body_kind:
		_wear_body(state["body"])
	var next_team: String = MatchRules.valid_team(state.get("team"))
	if next_team != team:
		team = next_team
		player_color = MatchRules.team_label_color(team) if team != "" else _own_color
	golden = state.get("golden") == true

	var weapon_name = state.get("weapon", "")
	if weapon_name != current_weapon:
		current_weapon = weapon_name
		_update_weapon_sprite()
	
	if state.has("behavior") and state.behavior != null:
		behavior = str(state.behavior)
	else:
		behavior = ""
	
	if label:
		if is_campaign_companion:
			label.text = "LATCH"
			label.modulate = LatchView.CYAN
		else:
			var hp_display = str(hp) + " HP"
			if hp < 30:
				hp_display = "!" + hp_display + "!"
		
			var score = int(state.get("score", 0))
			var score_chip = ""
			if score > 0:
				score_chip = " +" + str(score)
		
			# Stance beside callsign so follow / overview reads it without Tab.
			label.text = StanceChipScript.nameplate(player_name, behavior, hp_display, score_chip)
			# A side chip leads the plate so a spectator reads teams at a glance.
			if team != "":
				label.text = "[" + MatchRules.team_short(team) + "] " + label.text
			if golden:
				label.modulate = MatchRules.GOLD
			elif team != "":
				label.modulate = player_color
			elif behavior != "":
				label.modulate = StanceChipScript.accent_color(true)
			else:
				label.modulate = player_color
	
	if body and hit_flash_timer <= 0:
		_update_body_color(false)

## Only the local human body uses this path. Snapshot metadata still flows
## through update_state; the positional target is kept for safe fallback.
func set_predicted_position(value: Vector3, speed: float) -> void:
	prediction_active = true
	predicted_position = value
	predicted_speed = clampf(speed, 0.0, MoveStep.TOP_SPEED)


func clear_predicted_position() -> void:
	if prediction_active:
		prediction_active = false
		predicted_speed = 0.0
		position = target_position
		reset_remote_presentation()


func snap_authoritative_position() -> void:
	prediction_active = false
	predicted_speed = 0.0
	position = target_position
	reset_remote_presentation()


## MapInfo can replace geometry while retaining the same participants.
func reset_remote_presentation() -> void:
	remote_presentation.reset()
	presentation_yaw = target_yaw
	presentation_pitch = target_pitch

## Swap the legacy callsign strip for the accepted body. The field and feet
## registration match the Union bake, so the figure is exactly as tall as the
## shared hit volume: nothing here enlarges a body for readability.
func _wear_body(kind: String) -> void:
	var strip: Texture2D = load(PlayerBody.strip_path(kind))
	if strip == null or body == null:
		return
	body_kind = kind
	body.texture = strip
	body.hframes = PlayerBody.IDLE_FRAMES + PlayerBody.WALK_FRAMES
	body.vframes = 1
	body.frame = 0
	body.pixel_size = EnemyAnimation.VIEW_SIZE / EnemyAnimation.TILE
	body.position.y = EnemyAnimation.CENTRE_HEIGHT - EnemyView.CAMERA.FP_SERVER_REFERENCE_Y
	# The held weapon sits at the resting hands, about hip height.
	weapon_sprite.position = Vector3(0.34, 0.0, 0.02)
	muzzle.position = Vector3(0.64, 0.2, 0.04)
	# The plate rides just over a 1.8 metre head, not over the old tall strip.
	label.position.y = 0.65
	_update_body_color(false)

func _update_weapon_sprite():
	if not weapon_sprite:
		return
	if is_campaign_enemy or is_campaign_companion:
		weapon_sprite.visible = false
		return
	
	if current_weapon == "" or not weapon_textures.has(current_weapon):
		weapon_sprite.visible = false
		return
	
	var texture: Texture2D = weapon_textures[current_weapon]
	weapon_sprite.texture = texture
	# Side profiles share one texel density, so a pistol is visibly smaller
	# than a railgun. An 80-texel rifle spans what the old 32-pixel icon did.
	weapon_sprite.pixel_size = weapon_pixel_size * HELD_PROFILE_SCALE
	weapon_sprite.visible = true
	# Preserve weapon plate readability; light bone lift, not neon wash.
	weapon_sprite.modulate = Color(1.05, 1.02, 0.98)

func _update_body_color(hit: bool):
	if not body:
		return
	
	if hit:
		body.modulate = Color(1.55, 0.35, 0.28)
	elif is_campaign_companion:
		body.modulate = Color.WHITE
	elif is_campaign_enemy:
		body.modulate = Color.WHITE
	elif golden:
		# The golden Railgun's holder glows so everyone knows who to chase.
		body.modulate = Color(1.0, 1.0, 1.0).lerp(MatchRules.GOLD, 0.6) * 1.25
	elif not body_kind.is_empty() and team != "union":
		# A free body keeps its own bone, leather, rust and ember, with or
		# without a side: the coalition is who these people already are,
		# and the side still reads from the plate and the side chip.
		body.modulate = Color.WHITE
	elif team != "":
		# Sides read from the body, not only the plate: Union dark plate,
		# coalition bone.
		body.modulate = Color(1.0, 1.0, 1.0).lerp(MatchRules.team_body_color(team), 0.55)
	else:
		# Near-white multiply so Cyanex/Kragge pixel art reads; brand on label.
		body.modulate = Color(1.0, 1.0, 1.0).lerp(player_color, 0.18)
	_apply_body_scale(hit)

func _update_notary_shadow() -> void:
	if _notary_shadow == null:
		return
	var feet: Vector3 = global_position - Vector3.UP * 1.5
	var floor_y: float = NotaryAnimation.support(feet)
	_notary_shadow.position.y = floor_y - global_position.y + 0.014
	_notary_shadow.visible = hp > 0

## Alternates the third-person flash left and right from one shot to the next.
var _flash_mirrored: bool = false

func show_muzzle_flash(weapon: String):
	if is_campaign_enemy and campaign_actor.get("kind") == "notary":
		# Its shutter and optic have their own server-driven presentation.
		return
	if is_campaign_companion:
		if latch_view != null:
			latch_view.shot()
		if fire_sound:
			fire_sound.stream = fire_streams.get(weapon)
			if fire_sound.stream != null:
				fire_sound.play()
		return
	if enemy_view != null:
		enemy_view.shot()
	if weapon == "Fists" or weapon == "Shiv":
		if muzzle:
			muzzle.visible = false
		if muzzle_glow:
			muzzle_glow.light_energy = 0.0
		# A Crawler's leap resolves as a Fists contact; it is not a punch.
		if fire_sound and not is_campaign_enemy and melee_streams.has(weapon):
			fire_sound.stream = melee_streams[weapon]
			fire_sound.play()
		return
	if fire_sound:
		fire_sound.stream = fire_streams.get(weapon)
		if is_campaign_enemy and campaign_actor.get("kind") == "ranged_sweeper" and ranged_fire_stream != null:
			fire_sound.stream = ranged_fire_stream
		if fire_sound.stream:
			fire_sound.play()
	if weapon == "Scatter":
		_start_shotgun_cycle()
	
	if not muzzle:
		return
	
	var flash_time = 0.06
	if weapon == "Rail":
		muzzle.texture = rail_beam_texture
		# Gunmetal / cold bone, not neon.
		muzzle.modulate = Color(0.72, 0.78, 0.82)
		muzzle.scale = Vector3.ONE * 2.8
		flash_time = 0.10
		if muzzle_glow:
			muzzle_glow.light_color = Color(0.45, 0.52, 0.55)
			muzzle_glow.light_energy = 4.2
			muzzle_glow.omni_range = 5.5
	elif weapon == "Sniper":
		# A small orange-white flash with little light: no beam, a hard crack.
		muzzle.texture = muzzle_flash_texture
		muzzle.modulate = Color(1.0, 0.82, 0.6)
		muzzle.scale = Vector3.ONE * 1.4
		flash_time = 0.05
		if muzzle_glow:
			muzzle_glow.light_color = Color(0.62, 0.6, 0.55)
			muzzle_glow.light_energy = 1.6
			muzzle_glow.omni_range = 3.0
	elif weapon == "Scatter":
		muzzle.texture = muzzle_flash_texture
		muzzle.modulate = Color(0.95, 0.55, 0.28)
		muzzle.scale = Vector3.ONE * 2.6
		flash_time = 0.08
		if muzzle_glow:
			muzzle_glow.light_color = Color(0.85, 0.42, 0.16)
			muzzle_glow.light_energy = 4.0
			muzzle_glow.omni_range = 4.5
	else:
		# Flechette: tight ember needle.
		muzzle.texture = muzzle_flash_texture
		muzzle.modulate = Color(0.92, 0.78, 0.55)
		muzzle.scale = Vector3.ONE * 1.7
		if muzzle_glow:
			muzzle_glow.light_color = Color(0.78, 0.55, 0.28)
			muzzle_glow.light_energy = 2.8
			muzzle_glow.omni_range = 3.2
	
	# Each gun shows its own palette flash; the branches above set its size and
	# light. Mirroring every other shot keeps a burst from looking stamped.
	var drawn: Texture2D = ShotVfx.muzzle(weapon)
	if drawn != null:
		muzzle.texture = drawn
		muzzle.modulate = Color.WHITE
		_flash_mirrored = not _flash_mirrored
		muzzle.flip_h = _flash_mirrored
	muzzle.visible = true
	
	await get_tree().create_timer(flash_time).timeout
	if is_instance_valid(muzzle):
		muzzle.visible = false
		muzzle.scale = Vector3.ONE
		if muzzle_glow:
			muzzle_glow.light_energy = 0.0

## Feedback for being hit. `weapon` is the gun that did it.
##
## When it is unknown this used to fall back to `current_weapon`, which is the
## weapon this fighter is *holding*, not the one that shot them: being shot by
## a rail while carrying a scatter played the scatter's impact. The generic
## impact is the honest sound for an unknown shooter. The weapon reaches here
## properly once shot results carry it; see plans/shot-feedback.md.
func show_hit_feedback(weapon: String = ""):
	if hit_sound:
		if weapon != "" and hit_streams.has(weapon):
			hit_sound.stream = hit_streams[weapon]
		elif generic_hit_stream != null:
			hit_sound.stream = generic_hit_stream
		if hit_sound.stream:
			hit_sound.play()
	
	hit_flash_timer = 0.25
	_update_body_color(true)
	
	await get_tree().create_timer(0.12).timeout
	if is_instance_valid(body):
		_apply_body_scale(hit_flash_timer > 0)

## The resolved shot names the gun that landed, so the struck body answers
## with that gun's impact. The health drop in the same snapshot has already
## started the generic hit on this player, and this replaces it at once.
func play_impact(weapon: String) -> void:
	if hit_sound == null:
		return
	var stream: AudioStream = hit_streams.get(weapon, generic_hit_stream)
	if stream == null:
		return
	hit_sound.stream = stream
	hit_sound.play()
	impact_count += 1

func _start_shotgun_cycle() -> void:
	if _cycle_timer == null or cycle_sound == null or cycle_sound.stream == null \
			or not _cycle_timer.is_inside_tree():
		return
	_cycle_timer.start(SHOTGUN_CYCLE_DELAY)

func _on_shotgun_cycle() -> void:
	# A fighter who fell or put the Shotgun away does not work the action.
	if hp <= 0 or current_weapon != "Scatter" or cycle_sound == null:
		return
	cycle_sound.play()
	cycle_count += 1

## The authoritative drop to zero health. A Union machine falls as a machine;
## the Notary keeps its own crash where it lands.
func _play_down() -> void:
	if down_sound == null:
		return
	var kind: String = str(campaign_actor.get("kind", "")) if is_campaign_enemy else ""
	if kind == "notary":
		return
	var stream: AudioStream = down_robot_stream if kind in ROBOT_KINDS else down_body_stream
	if stream == null:
		return
	down_sound.stream = stream
	down_sound.play()
	down_count += 1

## A Union windup is announced once, at its authoritative start. Any other
## phase silences it, so breaking sight also cuts off a Turret's charge.
func _update_tell() -> void:
	if tell_sound == null:
		return
	if not is_campaign_enemy or campaign_actor.get("phase") != "windup":
		if tell_sound.playing:
			tell_sound.stop()
		return
	var started: Variant = campaign_actor.get("phase_started")
	var ends: Variant = campaign_actor.get("phase_ends")
	if not EquipmentState.integer(started, EquipmentState.MAX_EXACT_INTEGER) \
			or not EquipmentState.integer(ends, EquipmentState.MAX_EXACT_INTEGER) \
			or int(started) == _tell_started:
		return
	_tell_started = int(started)
	var kind: String = str(campaign_actor.get("kind", ""))
	if not tell_streams.has(kind):
		return
	var stream: AudioStream = tell_streams[kind]
	tell_sound.stream = stream
	tell_sound.pitch_scale = tell_pitch(kind, stream.get_length(),
		float(int(ends) - int(started)) * MoveStep.DT_LIVE)
	tell_sound.play()
	tell_count += 1

## Charge-shaped tells are sped up or slowed to end with the actual windup,
## within a range that keeps them recognisable. Other tells play as authored.
static func tell_pitch(kind: String, cue_seconds: float, windup_seconds: float) -> float:
	if kind not in STRETCHED_TELLS or cue_seconds <= 0.0 or windup_seconds <= 0.0:
		return 1.0
	return clampf(cue_seconds / windup_seconds, TELL_PITCH_MIN, TELL_PITCH_MAX)

func get_weapon_name() -> String:
	return current_weapon

func show_winner_glow():
	var tween = create_tween()
	tween.set_parallel(true)
	
	if body:
		tween.tween_property(body, "modulate", Color(2.0, 2.0, 2.0), 0.1)
		tween.tween_property(body, "modulate", Color.WHITE, 0.9).set_delay(0.1)

func set_highlighted(highlighted: bool):
	is_highlighted = highlighted
	if highlight:
		highlight.visible = highlighted

## Pure scale curve for far spectators. Safe to call from headless tests.
static func compute_far_cam_scale(distance: float) -> float:
	if distance <= FAR_CAM_REF_DIST:
		return 1.0
	return minf(distance / FAR_CAM_REF_DIST, FAR_CAM_MAX_SCALE)

## Nameplate scale: capped on screen up close, and sharing the far camera's
## growth beyond the reference distance so a distant fighter is still labelled.
static func compute_nameplate_scale(distance: float) -> float:
	if distance < NAMEPLATE_NEAR_DIST:
		return maxf(distance / NAMEPLATE_NEAR_DIST, NAMEPLATE_MIN_SCALE)
	return compute_far_cam_scale(distance)

func _update_far_cam_scale() -> void:
	var cam: Camera3D = get_viewport().get_camera_3d() if get_viewport() else null
	var dist: float = FAR_CAM_REF_DIST
	if cam != null:
		dist = global_position.distance_to(cam.global_position)
	_far_cam_scale = compute_far_cam_scale(dist) if broadcast_scale_enabled else 1.0
	_apply_body_scale(hit_flash_timer > 0)
	if label:
		label.scale = Vector3.ONE * compute_nameplate_scale(dist)

func _apply_body_scale(hit: bool) -> void:
	if not body:
		return
	if is_campaign_enemy or is_campaign_companion:
		# Fixed feet registration and silhouette size preserve the cover contract.
		body.scale = Vector3.ONE
		return
	var mult: float = _far_cam_scale
	if hit:
		mult *= HIT_SCALE_BOOST
	body.scale = Vector3.ONE * mult

func set_local_fp(enabled: bool) -> void:
	# Hide local billboard in FP so the HUD viewmodel owns the scrap face.
	is_local_fp = enabled
	if body:
		body.visible = not enabled and not is_campaign_companion
	if label:
		label.visible = nameplate_enabled and not enabled
	if highlight:
		highlight.visible = false if enabled else is_highlighted
	if weapon_sprite and enabled:
		weapon_sprite.visible = false
	elif weapon_sprite:
		_update_weapon_sprite()

func set_nameplate_enabled(enabled: bool) -> void:
	nameplate_enabled = enabled
	if label:
		label.visible = enabled and not is_local_fp
