extends Node
class_name ClientRetirement

## Scene-independent resource retirement. Decoder release needs a mixer turn;
## pending Compatibility skies need a completed draw before their RID is freed.
## The owner survives a return to the menu and drains before application quit.
const META: StringName = &"fragr_client_retirement"
const DEADLINE_MS: int = 2000

signal quit_ready(exit_code: int)

var _tree: SceneTree
var _environments: Array[Environment] = []
var _audio: Array[WeakRef] = []
var _draw_epoch: int = 0
var _required_draw: int = 0
var _quitting: bool = false

static func for_tree(tree: SceneTree) -> ClientRetirement:
	var existing: Variant = tree.get_meta(META) if tree.has_meta(META) else null
	if is_instance_valid(existing) and existing is ClientRetirement:
		return existing as ClientRetirement
	var owner: ClientRetirement = ClientRetirement.new()
	owner.name = "ClientRetirement"
	owner.process_mode = Node.PROCESS_MODE_ALWAYS
	owner._tree = tree
	tree.set_meta(META, owner)
	# Install before the deferred add: an immediate close must use the same owner.
	tree.auto_accept_quit = false
	tree.root.close_requested.connect(owner.request_quit)
	tree.node_removed.connect(owner._node_removed)
	if DisplayServer.get_name() != "headless":
		RenderingServer.frame_post_draw.connect(owner._post_draw)
	# Main-scene _ready can run while the root is adding children.
	tree.root.add_child.call_deferred(owner)
	return owner

func retain_environment(environment: Environment) -> void:
	if environment == null or DisplayServer.get_name() == "headless":
		return
	if not _environments.has(environment):
		_environments.append(environment)
	# First draw consumes pending sky allocations. The next consumes their frees.
	_required_draw = _draw_epoch + 2

func track_audio(scene: Node) -> void:
	_track_voice(scene)
	for node: Node in scene.find_children("*", "", true, false):
		_track_voice(node)

func _track_voice(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
		if node.has_stream_playback():
			var playback: AudioStreamPlayback = node.get_stream_playback()
			for reference: WeakRef in _audio:
				if reference.get_ref() == playback:
					return
			_audio.append(weakref(playback))

func _node_removed(node: Node) -> void:
	# Children leave before a parent's _exit_tree can stop and clear its voices.
	_track_voice(node)
	if node is WorldEnvironment:
		retain_environment(node.environment)

func _post_draw() -> void:
	_draw_epoch += 1
	_environments.clear()

func _process(_delta: float) -> void:
	_reap_audio()

func _reap_audio() -> void:
	for index: int in range(_audio.size() - 1, -1, -1):
		if _audio[index].get_ref() == null:
			_audio.remove_at(index)

func drained() -> bool:
	_reap_audio()
	return _audio.is_empty() and _environments.is_empty() and _draw_epoch >= _required_draw

func drain() -> bool:
	if not is_inside_tree():
		await _tree.process_frame
	var deadline: int = Time.get_ticks_msec() + DEADLINE_MS
	var forced_epoch: int = -1
	while not drained() and Time.get_ticks_msec() < deadline:
		# Minimized/hidden windows skip normal draws. Pump only an outstanding
		# retirement epoch, without presenting or queueing another draw until its
		# completion is observed. Headless checks never enter the renderer.
		if DisplayServer.get_name() != "headless" and _draw_epoch < _required_draw \
				and (not DisplayServer.window_can_draw(_tree.root.get_window_id()) or not RenderingServer.render_loop_enabled) \
				and forced_epoch != _draw_epoch:
			forced_epoch = _draw_epoch
			RenderingServer.force_draw(false)
		await _tree.process_frame
	if not drained():
		push_error("client_retirement: exit still owns %d audio playbacks and %d pending environments (draw %d/%d)" % [_audio.size(), _environments.size(), _draw_epoch, _required_draw])
		return false
	return true

func request_quit(exit_code: int = 0) -> void:
	if _quitting:
		return
	_quitting = true
	MouseCapture.release()
	_finish_quit.call_deferred(exit_code)

func _finish_quit(exit_code: int) -> void:
	track_audio(_tree.root)
	for child: Node in _tree.root.get_children():
		if child != self:
			child.queue_free()
	await _tree.process_frame
	if not await drain():
		exit_code = 1
	quit_ready.emit(exit_code)
	_tree.quit(exit_code)

func _exit_tree() -> void:
	if RenderingServer.frame_post_draw.is_connected(_post_draw):
		RenderingServer.frame_post_draw.disconnect(_post_draw)
	if _tree.node_removed.is_connected(_node_removed):
		_tree.node_removed.disconnect(_node_removed)
	if _tree.root.close_requested.is_connected(request_quit):
		_tree.root.close_requested.disconnect(request_quit)
	_environments.clear()
