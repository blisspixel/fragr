extends SceneTree

## Register a native reduced drawing at the same hand scale and bottom edge.
func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 2:
		_fail("require input PNG and output PNG")
		return
	var source: Image = Image.load_from_file(args[0])
	if source == null or source.get_size() != Vector2i(193, 144):
		_fail("require the untrimmed 193x144 native reduction")
		return
	var canvas: Image = Image.create(241, 180, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0, 0, 0, 0))
	canvas.blit_rect(source, Rect2i(0, 0, 193, 144), Vector2i(24, 36))
	if canvas.save_png(args[1]) != OK:
		_fail("cannot save registered picture")
		return
	for y: int in range(144):
		for x: int in range(193):
			if canvas.get_pixel(x + 24, y + 36) != source.get_pixel(x, y):
				_fail("registration altered a source pixel")
				return
	print("register_sniper_sprite: PASS unchanged reduced pixels, common canvas and bottom registration")
	quit(0)

func _fail(message: String) -> void:
	push_error("register_sniper_sprite: " + message)
	quit(1)
