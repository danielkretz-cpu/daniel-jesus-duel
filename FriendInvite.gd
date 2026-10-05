extends RefCounted
## Invitations contain a public room code only. Never copy the current URL or a token.
const PUBLIC_URL := "https://danielkretz-cpu.github.io/daniel-jesus-duel/"
const ROOM_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

static func normalized_code(value: String) -> String:
	return value.strip_edges().to_upper()

static func valid_code(value: String) -> bool:
	if value.length() != 8:
		return false
	for character in value:
		if not character in ROOM_ALPHABET:
			return false
	return true

static func room_from_input(value: String) -> String:
	var normalized := normalized_code(value)
	if valid_code(normalized):
		return normalized
	return room_from_url(value)

static func room_from_url(value: String) -> String:
	# Query and hash formats may be pasted, but duplicate/ambiguous rooms fail closed.
	var query := ""
	if "?" in value:
		query = value.split("?", true, 1)[1].split("#", true, 1)[0]
	elif "#" in value:
		query = value.split("#", true, 1)[1].trim_prefix("?")
	elif value.begins_with("room="):
		query = value
	else:
		return ""
	var found := ""
	var count := 0
	for parameter in query.split("&"):
		var parts := parameter.split("=", true, 1)
		if parts.size() == 2 and parts[0].uri_decode() == "room":
			count += 1
			found = normalized_code(parts[1].replace("+", " ").uri_decode())
	return found if count == 1 and valid_code(found) else ""

static func share_url(room_code: String) -> String:
	var normalized := normalized_code(room_code)
	return PUBLIC_URL + "?room=" + normalized.uri_encode() if valid_code(normalized) else ""

static func current_room() -> String:
	if OS.has_feature("web"):
		var location = JavaScriptBridge.eval("window.location.href")
		if location is String:
			return room_from_url(location)
	# Useful for native testing and an explicit native invite launch.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--room="):
			return room_from_input(arg.trim_prefix("--room="))
	return ""
