extends Node

## InvokeAI HTTP client for image generation via Flux2.
## Uses GameState.invoke_url for the backend address.

signal generation_started
signal generation_progress(percent: float)
signal generation_completed(image_name: String)
signal generation_failed(error: String)

var _http: HTTPRequest
var _poll_http: HTTPRequest

# Cached model keys resolved from the InvokeAI API.
var _main_model_key: String = ""
var _vae_model_key: String = ""
var _qwen3_encoder_key: String = ""
var _models_resolved: bool = false


# ══════════════════════════════════════════════════════════════════════════════
# Lifecycle
# ══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 300.0
	add_child(_http)

	_poll_http = HTTPRequest.new()
	_poll_http.timeout = 30.0
	add_child(_poll_http)


# ══════════════════════════════════════════════════════════════════════════════
# Public API
# ══════════════════════════════════════════════════════════════════════════════

## Generate an image and return the image name.
func generate_image(prompt: String, width: int = 512, height: int = 512) -> String:
	generation_started.emit()

	if not _models_resolved:
		var ok := await _resolve_models()
		if not ok:
			var err_msg := "InvokeService: could not resolve InvokeAI models"
			push_error(err_msg)
			generation_failed.emit(err_msg)
			return ""

	# 1. Enqueue batch.
	var graph := _build_flux2_graph(prompt, width, height)
	var batch_body := {
		"batch": {
			"graph": graph,
			"runs": 1,
		}
	}

	var enqueue_result := await _post_json("/api/v1/queue/default/enqueue_batch", batch_body)
	if enqueue_result.is_empty():
		var err_msg := "InvokeService: enqueue_batch failed"
		push_error(err_msg)
		generation_failed.emit(err_msg)
		return ""

	var batch_id: String = enqueue_result.get("batch", {}).get("batch_id", "")
	if batch_id.is_empty():
		# Try alternate response shape.
		batch_id = enqueue_result.get("batch_id", "")
	if batch_id.is_empty():
		var err_msg := "InvokeService: no batch_id in enqueue response"
		push_error(err_msg)
		generation_failed.emit(err_msg)
		return ""

	# 2. Poll for completion.
	var completed := await _poll_batch(batch_id)
	if not completed:
		var err_msg := "InvokeService: generation timed out or failed for batch %s" % batch_id
		push_error(err_msg)
		generation_failed.emit(err_msg)
		return ""

	# 3. Retrieve the latest generated image name.
	var img_name := await _get_latest_image()
	if img_name.is_empty():
		var err_msg := "InvokeService: could not retrieve generated image name"
		push_error(err_msg)
		generation_failed.emit(err_msg)
		return ""

	generation_completed.emit(img_name)
	return img_name


## Generate a small 64x64 object icon image.
func generate_object_image(object_name: String, style: String) -> String:
	var prompt := "%s, %s style, white background, game item icon, centered, simple" % [object_name, style]
	return await generate_image(prompt, 64, 64)


## Full URL for an image.
func image_url(image_name: String) -> String:
	return "%s/api/v1/images/i/%s/full" % [GameState.invoke_url.rstrip("/"), image_name]


## Thumbnail URL for an image.
func thumbnail_url(image_name: String) -> String:
	return "%s/api/v1/images/i/%s/thumbnail" % [GameState.invoke_url.rstrip("/"), image_name]


## Download image bytes.
func download_image(image_name: String) -> PackedByteArray:
	var url := image_url(image_name)
	var err := _http.request(url)
	if err != OK:
		push_error("InvokeService: download request error %d" % err)
		return PackedByteArray()

	var response: Array = await _http.request_completed
	var result_code: int = response[0]
	var http_code: int = response[1]
	var body: PackedByteArray = response[3]

	if result_code != HTTPRequest.RESULT_SUCCESS or http_code < 200 or http_code >= 300:
		push_error("InvokeService: download failed – HTTP %d, result %d" % [http_code, result_code])
		return PackedByteArray()

	return body


## Upload image bytes and return the image name.
func upload_image(bytes: PackedByteArray, filename: String) -> String:
	var url := "%s/api/v1/images/upload" % GameState.invoke_url.rstrip("/")

	# Build multipart form data.
	var boundary := "----GodotBoundary%d" % randi()
	var body := PackedByteArray()

	# File part.
	var header_part := (
		"--%s\r\n" % boundary
		+ 'Content-Disposition: form-data; name="file"; filename="%s"\r\n' % filename
		+ "Content-Type: image/png\r\n\r\n"
	)
	body.append_array(header_part.to_utf8_buffer())
	body.append_array(bytes)
	body.append_array(("\r\n--%s--\r\n" % boundary).to_utf8_buffer())

	var headers := PackedStringArray([
		"Content-Type: multipart/form-data; boundary=%s" % boundary,
	])

	var err := _http.request_raw(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		push_error("InvokeService: upload request error %d" % err)
		return ""

	var response: Array = await _http.request_completed
	var result_code: int = response[0]
	var http_code: int = response[1]
	var response_body: PackedByteArray = response[3]

	if result_code != HTTPRequest.RESULT_SUCCESS or http_code < 200 or http_code >= 300:
		push_error("InvokeService: upload failed – HTTP %d" % http_code)
		return ""

	var json := JSON.new()
	var parse_err := json.parse(response_body.get_string_from_utf8())
	if parse_err != OK:
		push_error("InvokeService: upload response parse error")
		return ""

	return json.data.get("image_name", "") if json.data is Dictionary else ""


## Test connectivity to the InvokeAI backend.
func test_connection() -> bool:
	var url := "%s/api/v1/app/version" % GameState.invoke_url.rstrip("/")
	var err := _http.request(url)
	if err != OK:
		return false

	var response: Array = await _http.request_completed
	var result_code: int = response[0]
	var http_code: int = response[1]
	return result_code == HTTPRequest.RESULT_SUCCESS and http_code == 200


# ══════════════════════════════════════════════════════════════════════════════
# Model resolution
# ══════════════════════════════════════════════════════════════════════════════

func _resolve_models() -> bool:
	_main_model_key = await _fetch_first_model_key("main")
	_vae_model_key = await _fetch_first_model_key("vae")
	_qwen3_encoder_key = await _fetch_first_model_key("qwen3_encoder")

	if _main_model_key.is_empty():
		push_error("InvokeService: no main model found on InvokeAI")
		return false

	_models_resolved = true
	return true


func _fetch_first_model_key(model_type: String) -> String:
	var url := "%s/api/v2/models/?model_type=%s" % [GameState.invoke_url.rstrip("/"), model_type]
	var err := _http.request(url)
	if err != OK:
		push_error("InvokeService: model list request error %d for type %s" % [err, model_type])
		return ""

	var response: Array = await _http.request_completed
	var result_code: int = response[0]
	var http_code: int = response[1]
	var body: PackedByteArray = response[3]

	if result_code != HTTPRequest.RESULT_SUCCESS or http_code < 200 or http_code >= 300:
		push_warning("InvokeService: could not fetch %s models – HTTP %d" % [model_type, http_code])
		return ""

	var json := JSON.new()
	var parse_err := json.parse(body.get_string_from_utf8())
	if parse_err != OK:
		return ""

	var data = json.data
	var models_array: Array = []
	if data is Dictionary:
		models_array = data.get("models", [])
	elif data is Array:
		models_array = data

	if models_array.is_empty():
		return ""

	# Return the key of the first model found.
	var first_model: Dictionary = models_array[0]
	return first_model.get("key", first_model.get("model_name", ""))


# ══════════════════════════════════════════════════════════════════════════════
# Graph building
# ══════════════════════════════════════════════════════════════════════════════

func _vae_dict() -> Variant:
	if _vae_model_key.is_empty():
		return null
	return {"key": _vae_model_key}


func _qwen3_dict() -> Variant:
	if _qwen3_encoder_key.is_empty():
		return null
	return {"key": _qwen3_encoder_key}


func _build_flux2_graph(prompt: String, width: int, height: int) -> Dictionary:
	var seed_value := randi()

	var nodes := {
		"model_loader": {
			"id": "model_loader",
			"type": "flux2_klein_model_loader",
			"model": {"key": _main_model_key},
			"vae_model": _vae_dict(),
			"qwen3_encoder_model": _qwen3_dict(),
		},
		"positive_text": {
			"id": "positive_text",
			"type": "flux2_klein_text_encoder",
			"prompt": prompt,
		},
		"denoise": {
			"id": "denoise",
			"type": "flux2_denoise",
			"width": width,
			"height": height,
			"num_steps": 4,
			"scheduler": "euler",
			"cfg_scale": 1.0,
			"guidance": 4.0,
			"seed": seed_value,
		},
		"decode": {
			"id": "decode",
			"type": "flux2_vae_decode",
		},
		"core_metadata": {
			"id": "core_metadata",
			"type": "core_metadata",
			"generation_mode": "txt2img",
			"positive_prompt": prompt,
			"width": width,
			"height": height,
			"seed": seed_value,
		},
		"save_image": {
			"id": "save_image",
			"type": "save_image",
			"is_intermediate": false,
			"board_id": "none",
		},
	}

	# Remove null model references.
	if _vae_model_key.is_empty():
		nodes["model_loader"].erase("vae_model")
	if _qwen3_encoder_key.is_empty():
		nodes["model_loader"].erase("qwen3_encoder_model")

	var edges := [
		# model_loader -> positive_text (clip)
		{
			"source": {"node_id": "model_loader", "field": "clip"},
			"destination": {"node_id": "positive_text", "field": "clip"},
		},
		# model_loader -> denoise (unet)
		{
			"source": {"node_id": "model_loader", "field": "unet"},
			"destination": {"node_id": "denoise", "field": "unet"},
		},
		# positive_text -> denoise (conditioning)
		{
			"source": {"node_id": "positive_text", "field": "conditioning"},
			"destination": {"node_id": "denoise", "field": "positive_conditioning"},
		},
		# denoise -> decode (latents)
		{
			"source": {"node_id": "denoise", "field": "latents"},
			"destination": {"node_id": "decode", "field": "latents"},
		},
		# model_loader -> decode (vae)
		{
			"source": {"node_id": "model_loader", "field": "vae"},
			"destination": {"node_id": "decode", "field": "vae"},
		},
		# decode -> save_image (image)
		{
			"source": {"node_id": "decode", "field": "image"},
			"destination": {"node_id": "save_image", "field": "image"},
		},
		# core_metadata -> save_image (metadata)
		{
			"source": {"node_id": "core_metadata", "field": "metadata"},
			"destination": {"node_id": "save_image", "field": "metadata"},
		},
	]

	return {
		"id": "invoker_gen",
		"nodes": nodes,
		"edges": edges,
	}


# ══════════════════════════════════════════════════════════════════════════════
# Batch polling
# ══════════════════════════════════════════════════════════════════════════════

func _poll_batch(batch_id: String) -> bool:
	var url := "%s/api/v1/queue/default/b/%s/status" % [GameState.invoke_url.rstrip("/"), batch_id]
	var max_attempts := 300  # ~5 minutes at 1-second intervals.
	var attempts := 0

	while attempts < max_attempts:
		var err := _poll_http.request(url)
		if err != OK:
			push_error("InvokeService: poll request error %d" % err)
			return false

		var response: Array = await _poll_http.request_completed
		var result_code: int = response[0]
		var http_code: int = response[1]
		var body: PackedByteArray = response[3]

		if result_code != HTTPRequest.RESULT_SUCCESS or http_code < 200 or http_code >= 300:
			push_warning("InvokeService: poll HTTP %d on attempt %d" % [http_code, attempts])
			await get_tree().create_timer(2.0).timeout
			attempts += 1
			continue

		var json := JSON.new()
		var parse_err := json.parse(body.get_string_from_utf8())
		if parse_err != OK:
			await get_tree().create_timer(1.0).timeout
			attempts += 1
			continue

		var data: Dictionary = json.data if json.data is Dictionary else {}
		var status: String = data.get("status", "")

		# Emit progress if available.
		var completed_count: int = data.get("completed", 0)
		var total_count: int = data.get("total", 1)
		if total_count > 0:
			generation_progress.emit(float(completed_count) / float(total_count) * 100.0)

		if status == "completed":
			return true
		elif status == "failed" or status == "canceled":
			push_error("InvokeService: batch %s ended with status '%s'" % [batch_id, status])
			return false

		# Still in progress – wait and retry.
		await get_tree().create_timer(1.0).timeout
		attempts += 1

	push_error("InvokeService: polling timed out for batch %s" % batch_id)
	return false


# ══════════════════════════════════════════════════════════════════════════════
# Image retrieval
# ══════════════════════════════════════════════════════════════════════════════

func _get_latest_image() -> String:
	var url := "%s/api/v1/images/?is_intermediate=false&limit=1&order_dir=desc" % GameState.invoke_url.rstrip("/")
	var err := _http.request(url)
	if err != OK:
		push_error("InvokeService: image list request error %d" % err)
		return ""

	var response: Array = await _http.request_completed
	var result_code: int = response[0]
	var http_code: int = response[1]
	var body: PackedByteArray = response[3]

	if result_code != HTTPRequest.RESULT_SUCCESS or http_code < 200 or http_code >= 300:
		push_error("InvokeService: image list failed – HTTP %d" % http_code)
		return ""

	var json := JSON.new()
	var parse_err := json.parse(body.get_string_from_utf8())
	if parse_err != OK:
		push_error("InvokeService: image list JSON parse error")
		return ""

	var data = json.data
	var items: Array = []
	if data is Dictionary:
		items = data.get("items", [])
	elif data is Array:
		items = data

	if items.is_empty():
		return ""

	return items[0].get("image_name", "")


# ══════════════════════════════════════════════════════════════════════════════
# HTTP helpers
# ══════════════════════════════════════════════════════════════════════════════

func _post_json(endpoint: String, body: Dictionary) -> Dictionary:
	var url := GameState.invoke_url.rstrip("/") + endpoint
	var json_body := JSON.stringify(body)
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json",
	])

	var err := _http.request(url, headers, HTTPClient.METHOD_POST, json_body)
	if err != OK:
		push_error("InvokeService: HTTP request error %d for %s" % [err, url])
		return {}

	var response: Array = await _http.request_completed
	var result_code: int = response[0]
	var http_code: int = response[1]
	var response_body: PackedByteArray = response[3]

	if result_code != HTTPRequest.RESULT_SUCCESS:
		push_error("InvokeService: request failed with result %d" % result_code)
		return {}

	if http_code < 200 or http_code >= 300:
		push_error("InvokeService: HTTP %d – %s" % [http_code, response_body.get_string_from_utf8()])
		return {}

	var json := JSON.new()
	var parse_err := json.parse(response_body.get_string_from_utf8())
	if parse_err != OK:
		push_error("InvokeService: JSON parse error – %s" % json.get_error_message())
		return {}

	return json.data if json.data is Dictionary else {}
