extends RefCounted

static func clean(path: String, original_copyright: String = "") -> bool:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.size() < 20 or bytes.decode_u32(0) != 0x46546c67 or bytes.decode_u32(4) != 2 or bytes.decode_u32(8) != bytes.size():
		return false
	var length: int = bytes.decode_u32(12)
	if length > bytes.size() - 20 or bytes.decode_u32(16) != 0x4e4f534a:
		return false
	var parsed: Variant = JSON.parse_string(bytes.slice(20, 20 + length).get_string_from_utf8())
	if not parsed is Dictionary or not parsed.get("asset") is Dictionary:
		return false
	# Optional software authorship is removed. Legal copyright is retained.
	parsed["asset"].erase("generator")
	if not original_copyright.is_empty():
		var existing: String = str(parsed["asset"].get("copyright", ""))
		if existing.is_empty():
			parsed["asset"]["copyright"] = original_copyright
		elif existing != original_copyright:
			parsed["asset"]["copyright"] = existing + "\n" + original_copyright
	var json: PackedByteArray = JSON.stringify(parsed).to_utf8_buffer()
	while json.size() % 4 != 0:
		json.append(32)
	var remainder: PackedByteArray = bytes.slice(20 + length)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_32(0x46546c67)
	file.store_32(2)
	file.store_32(20 + json.size() + remainder.size())
	file.store_32(json.size())
	file.store_32(0x4e4f534a)
	file.store_buffer(json)
	file.store_buffer(remainder)
	file.close()
	return true
