extends RefCounted

## Offline container operations. Accessor bytes are never decoded or re-exported.
static func read(path: String) -> Dictionary:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.size() < 28 or bytes.size() > 64 * 1024 * 1024 \
		or bytes.decode_u32(0) != 0x46546c67 or bytes.decode_u32(4) != 2 \
		or bytes.decode_u32(8) != bytes.size() or bytes.decode_u32(16) != 0x4e4f534a:
		return {}
	var length: int = bytes.decode_u32(12)
	if length % 4 != 0 or length > bytes.size() - 28:
		return {}
	var original_json: String = bytes.slice(20, 20 + length).get_string_from_utf8()
	var document: Variant = JSON.parse_string(original_json)
	var offset: int = 20 + length
	if not document is Dictionary or bytes.decode_u32(offset + 4) != 0x004e4942 \
		or bytes.decode_u32(offset) != bytes.size() - offset - 8:
		return {}
	return {"document": document, "binary": bytes.slice(offset + 8), "original_json": original_json}

static func write(path: String, document: Dictionary, binary: PackedByteArray, original_json: String = "") -> bool:
	var members: Dictionary = _raw_members(original_json) if not original_json.is_empty() else {}
	var values: PackedStringArray = []
	for key: String in document:
		# Preserve original decimal tokens as well as binary accessor bytes.
		# A parse/stringify round trip can otherwise move a double by one ULP.
		var unchanged: bool = members.has(key) and key not in ["asset", "bufferViews", "buffers", "images", "materials"]
		values.append(JSON.stringify(key) + ":" + (members[key] if unchanged else JSON.stringify(document[key], "", true, true)))
	var text_bytes: PackedByteArray = ("{" + ",".join(values) + "}").to_utf8_buffer()
	while text_bytes.size() % 4 != 0:
		text_bytes.append(32)
	while binary.size() % 4 != 0:
		binary.append(0)
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
		return false
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_32(0x46546c67)
	file.store_32(2)
	file.store_32(28 + text_bytes.size() + binary.size())
	file.store_32(text_bytes.size())
	file.store_32(0x4e4f534a)
	file.store_buffer(text_bytes)
	file.store_32(binary.size())
	file.store_32(0x004e4942)
	file.store_buffer(binary)
	file.close()
	return true

static func _raw_members(text: String) -> Dictionary:
	var members: Dictionary = {}
	var cursor: int = text.find("{") + 1
	while cursor > 0 and cursor < text.length():
		while cursor < text.length() and text[cursor] in [" ", "\t", "\r", "\n", ","]:
			cursor += 1
		if cursor >= text.length() or text[cursor] == "}":
			break
		if text[cursor] != "\"":
			return {}
		var key_start: int = cursor
		cursor += 1
		while cursor < text.length():
			if text[cursor] == "\\":
				cursor += 2
			elif text[cursor] == "\"":
				cursor += 1
				break
			else:
				cursor += 1
		var key: Variant = JSON.parse_string(text.substr(key_start, cursor - key_start))
		while cursor < text.length() and text[cursor] in [" ", "\t", "\r", "\n"]:
			cursor += 1
		if not key is String or cursor >= text.length() or text[cursor] != ":":
			return {}
		cursor += 1
		var value_start: int = cursor
		var depth: int = 0
		var quoted: bool = false
		while cursor < text.length():
			var token: String = text[cursor]
			if quoted:
				if token == "\\":
					cursor += 2
					continue
				if token == "\"":
					quoted = false
			elif token == "\"":
				quoted = true
			elif token in ["[", "{"]:
				depth += 1
			elif token in ["]", "}"]:
				if depth == 0:
					break
				depth -= 1
			elif token == "," and depth == 0:
				break
			cursor += 1
		members[key] = text.substr(value_start, cursor - value_start)
	return members
