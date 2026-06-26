extends Node

## Pexels API client for searching outfit/clothing images.

var _http: HTTPRequest
var _api_key: String = ""


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 15.0
	add_child(_http)
	_load_api_key()


func _load_api_key() -> void:
	var env_path := "res://.env"
	var file := FileAccess.open(env_path, FileAccess.READ)
	if file == null:
		push_warning("PexelsService: .env file not found")
		return
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.begins_with("PEXELS_API_KEY="):
			_api_key = line.substr("PEXELS_API_KEY=".length()).strip_edges()
			break
	file.close()
	if _api_key != "":
		print("PexelsService: API key loaded")


func is_available() -> bool:
	return _api_key != ""


func search_photos(query: String, per_page: int = 6) -> Array:
	if _api_key == "":
		push_error("PexelsService: no API key")
		return []

	var url := "https://api.pexels.com/v1/search?query=%s&per_page=%d" % [query.uri_encode(), per_page]
	var headers := PackedStringArray(["Authorization: %s" % _api_key])

	var err := _http.request(url, headers)
	if err != OK:
		push_error("PexelsService: request error %d" % err)
		return []

	var response: Array = await _http.request_completed
	var result_code: int = response[0]
	var http_code: int = response[1]
	var body: PackedByteArray = response[3]

	if result_code != HTTPRequest.RESULT_SUCCESS or http_code < 200 or http_code >= 300:
		push_error("PexelsService: HTTP %d" % http_code)
		return []

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		return []

	if not json.data is Dictionary:
		return []

	var photos: Array = json.data.get("photos", [])
	var results: Array = []
	for photo: Dictionary in photos:
		var src: Dictionary = photo.get("src", {})
		results.append({
			"id": photo.get("id", 0),
			"url_small": src.get("small", ""),
			"url_medium": src.get("medium", ""),
			"url_large": src.get("large", ""),
			"url_original": src.get("original", ""),
			"alt": photo.get("alt", ""),
			"photographer": photo.get("photographer", ""),
		})
	return results


func download_image(url: String) -> PackedByteArray:
	var headers := PackedStringArray(["Authorization: %s" % _api_key])
	var err := _http.request(url, headers)
	if err != OK:
		return PackedByteArray()

	var response: Array = await _http.request_completed
	var result_code: int = response[0]
	var http_code: int = response[1]
	var body: PackedByteArray = response[3]

	if result_code != HTTPRequest.RESULT_SUCCESS or http_code < 200 or http_code >= 300:
		return PackedByteArray()

	return body


func search_outfit_for_character(char_data: Dictionary) -> Array:
	var gender: String = char_data.get("sex", char_data.get("gender", "")).to_lower()
	var role: String = char_data.get("role", "")
	var personality: String = char_data.get("personality", "")
	var style: String = GameState.image_style

	var is_male: bool = gender == "male" or gender == "maschile" or gender == "m"
	var gender_word := "man" if is_male else "woman"

	var query := "%s fashion outfit" % gender_word
	if role != "":
		query = "%s %s outfit clothing" % [role, gender_word]
	elif personality != "":
		query = "%s fashion style" % gender_word

	return await search_photos(query, 6)
