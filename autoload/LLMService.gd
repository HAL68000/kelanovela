extends Node

## LLM HTTP client for OpenAI-compatible APIs (LM Studio / Ollama).
## Uses GameState for backend URL and model settings.

signal request_started
signal request_completed(success: bool)

var _http: HTTPRequest


# ══════════════════════════════════════════════════════════════════════════════
# Lifecycle
# ══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 120.0
	add_child(_http)


# ══════════════════════════════════════════════════════════════════════════════
# Public API
# ══════════════════════════════════════════════════════════════════════════════

## Send a chat completion request and return the assistant's content string.
func chat(
	messages: Array,
	system_prompt: String = "",
	temperature: float = 0.7,
	max_tokens: int = 4000
) -> String:
	var body := _build_chat_body(messages, system_prompt, temperature, max_tokens)
	var result := await _post_json("/v1/chat/completions", body)
	if result.is_empty():
		return ""
	var choices: Array = result.get("choices", [])
	if choices.is_empty():
		push_error("LLMService: no choices in response")
		return ""
	return choices[0].get("message", {}).get("content", "")


## Send a chat request and parse the response as JSON.
func chat_json(
	messages: Array,
	system_prompt: String = "",
	temperature: float = 0.1
) -> Dictionary:
	var raw := await chat(messages, system_prompt, temperature)
	if raw.is_empty():
		return {}
	return _extract_json(raw)


## Extract characters from a story text via LLM.
func extract_characters(story_text: String, max_characters: int = 6) -> Array:
	var system := "You are a character extraction assistant. Respond ONLY with valid JSON."
	var prompt := (
		"Extract up to %d characters from the following story. " % max_characters
		+ "Return JSON in this exact format:\n"
		+ '{"characters":[{"name":"...","age":"...","gender":"...","race":"...","skin_color":"...","hair_color":"...","height":"...","physical_traits":"...","outfit":["..."],"description":"..."}]}\n\n'
		+ "Story:\n" + story_text
	)
	var messages := [{"role": "user", "content": prompt}]
	var result := await chat_json(messages, system)
	return result.get("characters", [])


## Generate 3-5 possible objectives for the player.
func generate_objectives(story_preamble: String, story_type: String) -> Array:
	var system := "You are a creative game designer. Respond ONLY with valid JSON."
	var prompt := (
		"Given this story preamble and type, generate 3 to 5 possible objectives "
		+ "that a player character could pursue.\n\n"
		+ "Story type: %s\n" % story_type
		+ "Preamble:\n%s\n\n" % story_preamble
		+ 'Return JSON: {"objectives":["objective 1","objective 2",...]}'
	)
	var messages := [{"role": "user", "content": prompt}]
	var result := await chat_json(messages, system)
	return result.get("objectives", [])


## Generate the world: objects, NPC positions, initial tasks.
func generate_world(
	story_preamble: String,
	objective: String,
	npcs_list: Array,
	map_description: String
) -> Dictionary:
	var system := "You are a world-building assistant for an interactive fiction game. Respond ONLY with valid JSON."

	var npc_names: Array = []
	for npc in npcs_list:
		npc_names.append(npc.get("name", "unknown"))

	var prompt := (
		"Generate the initial world state for this game.\n\n"
		+ "Story: %s\n" % story_preamble
		+ "Player objective: %s\n" % objective
		+ "NPCs: %s\n" % str(npc_names)
		+ "Map rooms/areas: %s\n\n" % map_description
		+ "Return JSON:\n"
		+ '{\n'
		+ '  "objects": [{"name":"...","description":"...","category":"clothes|tools|weapons|medicine|food|jewelry|scrolls|machinery","location":"room_tag"}],\n'
		+ '  "npc_positions": {"npc_name":"room_tag"},\n'
		+ '  "initial_tasks": ["task description"]\n'
		+ '}'
	)
	var messages := [{"role": "user", "content": prompt}]
	return await chat_json(messages, system)


## Build an image-generation prompt from scene context.
func build_scene_prompt(
	scene_description: String,
	characters: Array,
	style: String
) -> String:
	var system := "You are a prompt engineer for image generation. Return ONLY the prompt text, no JSON."
	var char_descriptions: String = ""
	for c in characters:
		char_descriptions += "- %s: %s\n" % [c.get("name", ""), c.get("description", c.get("physical_traits", ""))]

	var prompt := (
		"Create a concise image generation prompt for this scene.\n\n"
		+ "Scene: %s\n" % scene_description
		+ "Characters present:\n%s" % char_descriptions
		+ "Art style: %s\n\n" % style
		+ "Write a single paragraph prompt suitable for Stable Diffusion / Flux. "
		+ "Include composition, lighting, mood. Do NOT include negative prompt."
	)
	var messages := [{"role": "user", "content": prompt}]
	return await chat(messages, system, 0.7, 500)


## Main gameplay chat. Returns narrative + actions + options.
func game_chat(player_message: String, context: Dictionary) -> Dictionary:
	var system := (
		"You are the game master of an interactive fiction game. "
		+ "Always respond in valid JSON with this structure:\n"
		+ '{"response":"narrative text","actions":[{"type":"change_outfit|create_object|destroy_object|change_mood|change_status|move_npc|move_player","params":{}}],"options":["option1","option2","option3"]}\n\n'
		+ "Available action types:\n"
		+ "- change_outfit: params {npc_name, slot, item}\n"
		+ "- create_object: params {name, description, category, location}\n"
		+ "- destroy_object: params {name}\n"
		+ "- change_mood: params {npc_name, mood}\n"
		+ "- change_status: params {npc_name, alive}\n"
		+ "- move_npc: params {npc_name, destination}\n"
		+ "- move_player: params {destination}\n\n"
		+ "Always provide 2-4 options for the player's next action."
	)

	var ctx_text := (
		"Current room: %s\n" % context.get("current_room", "unknown")
		+ "Nearby NPCs: %s\n" % str(context.get("nearby_npcs", []))
		+ "Player inventory: %s\n" % str(context.get("inventory", []))
		+ "Story state: %s\n" % context.get("story_state", "")
	)

	var messages: Array = context.get("history", []).duplicate()
	messages.append({
		"role": "user",
		"content": ctx_text + "\nPlayer: " + player_message,
	})

	var result := await chat_json(messages, system, 0.7)
	if result.is_empty():
		return {
			"response": "...",
			"actions": [],
			"options": ["Look around", "Wait"],
		}
	# Ensure expected keys exist.
	if not result.has("response"):
		result["response"] = "..."
	if not result.has("actions"):
		result["actions"] = []
	if not result.has("options"):
		result["options"] = ["Look around", "Wait"]
	return result


# ══════════════════════════════════════════════════════════════════════════════
# Internal helpers
# ══════════════════════════════════════════════════════════════════════════════

func _build_chat_body(
	messages: Array,
	system_prompt: String,
	temperature: float,
	max_tokens: int
) -> Dictionary:
	var all_messages: Array = []
	if system_prompt != "":
		all_messages.append({"role": "system", "content": system_prompt})
	all_messages.append_array(messages)
	return {
		"model": GameState.llm_model,
		"messages": all_messages,
		"temperature": temperature,
		"max_tokens": max_tokens,
	}


func _post_json(endpoint: String, body: Dictionary) -> Dictionary:
	request_started.emit()
	var url := GameState.llm_backend_url.rstrip("/") + endpoint
	var json_body := JSON.stringify(body)
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json",
	])

	var err := _http.request(url, headers, HTTPClient.METHOD_POST, json_body)
	if err != OK:
		push_error("LLMService: HTTP request error %d for %s" % [err, url])
		request_completed.emit(false)
		return {}

	var response: Array = await _http.request_completed
	# response = [result, response_code, headers, body]
	var result_code: int = response[0]
	var http_code: int = response[1]
	var response_body: PackedByteArray = response[3]

	if result_code != HTTPRequest.RESULT_SUCCESS:
		push_error("LLMService: request failed with result %d" % result_code)
		request_completed.emit(false)
		return {}

	if http_code < 200 or http_code >= 300:
		push_error("LLMService: HTTP %d – %s" % [http_code, response_body.get_string_from_utf8()])
		request_completed.emit(false)
		return {}

	var json := JSON.new()
	var parse_err := json.parse(response_body.get_string_from_utf8())
	if parse_err != OK:
		push_error("LLMService: JSON parse error – %s" % json.get_error_message())
		request_completed.emit(false)
		return {}

	request_completed.emit(true)
	return json.data if json.data is Dictionary else {}


## Extract JSON from a raw LLM response that may contain markdown fences,
## trailing commas, or line comments.
func _extract_json(raw: String) -> Dictionary:
	var text := raw.strip_edges()

	# Strip markdown code fences.
	var fence_regex := RegEx.new()
	fence_regex.compile("(?s)```(?:json)?\\s*(.*?)\\s*```")
	var fence_match := fence_regex.search(text)
	if fence_match:
		text = fence_match.get_string(1)

	# Find the outermost { ... } or [ ... ].
	var start := -1
	var open_char := ""
	var close_char := ""
	for i in range(text.length()):
		if text[i] == "{":
			open_char = "{"
			close_char = "}"
			start = i
			break
		elif text[i] == "[":
			open_char = "["
			close_char = "]"
			start = i
			break

	if start == -1:
		push_error("LLMService: no JSON object/array found in response")
		return {}

	# Find matching closing bracket, accounting for nesting.
	var depth := 0
	var end := -1
	var in_string := false
	var escape_next := false
	for i in range(start, text.length()):
		var c := text[i]
		if escape_next:
			escape_next = false
			continue
		if c == "\\":
			escape_next = true
			continue
		if c == '"':
			in_string = not in_string
			continue
		if in_string:
			continue
		if c == open_char:
			depth += 1
		elif c == close_char:
			depth -= 1
			if depth == 0:
				end = i
				break

	if end == -1:
		push_error("LLMService: unbalanced brackets in JSON response")
		return {}

	var json_str := text.substr(start, end - start + 1)

	# Remove single-line comments (// ...) outside strings.
	var comment_regex := RegEx.new()
	comment_regex.compile('(?m)^((?:[^"\\\\]|"(?:[^"\\\\]|\\\\.)*")*?)//.*$')
	json_str = comment_regex.sub(json_str, "$1", true)

	# Remove trailing commas before } or ].
	var comma_regex := RegEx.new()
	comma_regex.compile(",\\s*([}\\]])")
	json_str = comma_regex.sub(json_str, "$1", true)

	var json := JSON.new()
	var parse_err := json.parse(json_str)
	if parse_err != OK:
		push_error("LLMService: cleaned JSON still failed to parse – %s" % json.get_error_message())
		return {}

	if json.data is Dictionary:
		return json.data
	elif json.data is Array:
		# Wrap array results so callers always get a Dictionary.
		return {"result": json.data}
	return {}
