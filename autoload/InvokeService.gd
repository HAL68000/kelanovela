extends Node

## InvokeAI HTTP client for image generation via Flux2.
## Uses GameState.invoke_url for the backend address.

signal generation_started
signal generation_progress(percent: float)
signal generation_completed(image_name: String)
signal generation_failed(error: String)

var _http: HTTPRequest
var _poll_http: HTTPRequest

# Cached full model dicts resolved from the InvokeAI API.
var _main_model: Dictionary = {}
var _vae_model: Dictionary = {}
var _qwen3_encoder_model: Dictionary = {}
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

## List available main model names from InvokeAI.
func list_main_models() -> Array:
	var models: Array = await _fetch_models("main")
	var names: Array = []
	for m: Dictionary in models:
		var model_name: String = m.get("name", "")
		if model_name != "":
			names.append(model_name)
	return names


## Upload a local image file to InvokeAI and return the image_name.
## This is needed to use images as kontext references during generation.
func upload_local_image(file_path: String) -> String:
	var img := Image.new()
	if img.load(file_path) != OK:
		push_error("InvokeService: cannot load image at %s" % file_path)
		return ""
	var png_bytes := img.save_png_to_buffer()
	return await upload_image(png_bytes, file_path.get_file().get_basename() + ".png")


## Generate an image with optional reference images (kontext).
## ref_image_names: Array of InvokeAI image_name strings to use as visual context.
func generate_image(prompt: String, width: int = 512, height: int = 512, ref_image_names: Array = []) -> String:
	generation_started.emit()

	# Always re-resolve models to pick up config changes
	_models_resolved = false
	var ok := await _resolve_models()
	if not ok:
		return ""

	# 1. Enqueue batch.
	var graph := _build_flux2_graph(prompt, width, height, ref_image_names)
	var batch_body := {
		"batch": {
			"graph": graph,
			"runs": 1,
		}
	}

	var enqueue_result := await _post_json("/api/v1/queue/default/enqueue_batch", batch_body)
	if enqueue_result.is_empty():
		var err_msg := "enqueue_batch fallito — controlla i log di InvokeAI. Modello: %s" % _main_model.get("name", "?")
		push_error("InvokeService: " + err_msg)
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

	# 3. Retrieve generated image name via session_id matching (like Flutter).
	var img_name: String = await _image_name_from_batch(batch_id)
	if img_name.is_empty():
		img_name = await _get_latest_image()
	if img_name.is_empty():
		var err_msg := "InvokeService: could not retrieve generated image name for batch %s" % batch_id
		push_error(err_msg)
		generation_failed.emit(err_msg)
		return ""

	print("InvokeService: generated image '%s'" % img_name)
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
	var base := GameState.invoke_url.rstrip("/")
	var url := "%s/api/v1/images/upload?image_category=user&is_intermediate=false" % base

	var boundary := "----GodotBoundary%d" % randi()
	var content_type := "image/png"
	if filename.ends_with(".jpg") or filename.ends_with(".jpeg"):
		content_type = "image/jpeg"
	elif filename.ends_with(".webp"):
		content_type = "image/webp"

	var body := PackedByteArray()
	var header_part := (
		"--%s\r\n" % boundary
		+ 'Content-Disposition: form-data; name="file"; filename="%s"\r\n' % filename
		+ "Content-Type: %s\r\n\r\n" % content_type
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
		push_error("InvokeService: upload failed – HTTP %d – %s" % [http_code, response_body.get_string_from_utf8().left(300)])
		return ""

	var json := JSON.new()
	if json.parse(response_body.get_string_from_utf8()) != OK:
		push_error("InvokeService: upload response parse error")
		return ""

	var img_name: String = json.data.get("image_name", "") if json.data is Dictionary else ""
	if img_name != "":
		print("InvokeService: uploaded image as '%s'" % img_name)
	return img_name


## Fetch image dimensions from InvokeAI.
func fetch_image_size(image_name: String) -> Dictionary:
	var encoded := image_name.uri_encode()
	var url := "%s/api/v1/images/i/%s" % [GameState.invoke_url.rstrip("/"), encoded]
	var err := _poll_http.request(url)
	if err != OK:
		return {}
	var response: Array = await _poll_http.request_completed
	var result_code: int = response[0]
	var http_code: int = response[1]
	var body: PackedByteArray = response[3]
	if result_code != HTTPRequest.RESULT_SUCCESS or http_code < 200 or http_code >= 300:
		return {}
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		return {}
	if json.data is Dictionary:
		var w: int = int(json.data.get("width", 0))
		var h: int = int(json.data.get("height", 0))
		if w > 0 and h > 0:
			return {"width": w, "height": h}
	return {}


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
# Model resolution (matches Flutter invoke_service.dart)
# ══════════════════════════════════════════════════════════════════════════════

func _resolve_models() -> bool:
	var all_main: Array = await _fetch_models("main")
	var all_vae: Array = await _fetch_models("vae")
	var all_qwen3: Array = await _fetch_models("qwen3_encoder")

	# Main model — prefer user-selected, fallback to first flux2
	var preferred: String = GameState.selected_invoke_model
	_main_model = {}
	if preferred != "":
		for m: Dictionary in all_main:
			if m.get("name", "") == preferred or m.get("key", "") == preferred:
				_main_model = _make_model_dict(m)
				break
	if _main_model.is_empty():
		_main_model = _pick_model(all_main, "flux2")
	if _main_model.is_empty():
		var names: Array = []
		for m: Dictionary in all_main:
			names.append("%s (base=%s)" % [m.get("name", "?"), m.get("base", "?")])
		var err_msg := "Nessun modello Flux2 trovato. Modelli disponibili: %s" % ", ".join(names)
		push_error("InvokeService: " + err_msg)
		generation_failed.emit(err_msg)
		return false

	# VAE — prefer flux2 base, fallback to any
	_vae_model = _pick_model(all_vae, "flux2")
	if _vae_model.is_empty():
		_vae_model = _pick_model(all_vae, "")

	# Qwen3 encoder — must match Klein variant (4b/8b/9b)
	_qwen3_encoder_model = _resolve_qwen3_for_main(_main_model, all_qwen3)

	_models_resolved = true
	print("InvokeService: models resolved – main=%s (base=%s)  vae=%s  qwen3=%s" % [
		_main_model.get("name", "?"),
		_main_model.get("base", "?"),
		_vae_model.get("name", "(none)"),
		_qwen3_encoder_model.get("name", "(none)"),
	])
	return true


func _resolve_qwen3_for_main(main_model: Dictionary, encoders: Array) -> Dictionary:
	if encoders.is_empty():
		return {}

	# Prefer the 8b encoder for most Flux2 models (default)
	# Only pick 4b if the main model name explicitly says 4b/klein_4b
	var probe := ("%s %s" % [main_model.get("name", ""), main_model.get("key", "")]).to_lower()
	var wanted := "8b"
	if probe.contains("klein_4b") or probe.contains("qwen3_4b") or probe.contains("qwen_3_4b"):
		wanted = "4b"

	var want_tokens: Array = []
	if wanted == "4b":
		want_tokens = ["qwen3_4b", "qwen_3_4b", "_4b"]
	else:
		want_tokens = ["qwen3_8b", "qwen_3_8b", "_8b", "fp8"]

	for enc: Dictionary in encoders:
		var enc_probe := ("%s %s" % [enc.get("name", ""), enc.get("key", "")]).to_lower()
		for token: String in want_tokens:
			if enc_probe.contains(token):
				print("InvokeService: matched qwen3 encoder '%s' for main model '%s'" % [enc.get("name", ""), main_model.get("name", "")])
				return {
					"key": enc.get("key", ""),
					"hash": enc.get("hash", ""),
					"name": enc.get("name", ""),
					"base": enc.get("base", ""),
					"type": enc.get("type", "qwen3_encoder"),
				}

	# Fallback: pick any encoder
	return _pick_model(encoders, "")


func _make_model_dict(m: Dictionary) -> Dictionary:
	return {
		"key": m.get("key", ""),
		"hash": m.get("hash", ""),
		"name": m.get("name", ""),
		"base": m.get("base", ""),
		"type": m.get("type", ""),
	}


func _pick_model(models: Array, required_base: String) -> Dictionary:
	for m: Dictionary in models:
		var base: String = m.get("base", "").to_lower()
		if required_base.is_empty() or base.contains(required_base.to_lower()):
			return {
				"key": m.get("key", ""),
				"hash": m.get("hash", ""),
				"name": m.get("name", ""),
				"base": m.get("base", ""),
				"type": m.get("type", ""),
			}
	return {}


func _fetch_models(model_type: String) -> Array:
	var url := "%s/api/v2/models/?model_type=%s" % [GameState.invoke_url.rstrip("/"), model_type]
	var err := _http.request(url)
	if err != OK:
		push_error("InvokeService: model list request error %d for type %s" % [err, model_type])
		return []

	var response: Array = await _http.request_completed
	var result_code: int = response[0]
	var http_code: int = response[1]
	var body: PackedByteArray = response[3]

	if result_code != HTTPRequest.RESULT_SUCCESS or http_code < 200 or http_code >= 300:
		push_warning("InvokeService: could not fetch %s models – HTTP %d" % [model_type, http_code])
		return []

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		return []

	var data = json.data
	if data is Dictionary:
		return data.get("models", [])
	elif data is Array:
		return data
	return []


# ══════════════════════════════════════════════════════════════════════════════
# Graph building — Flux2 Klein (matches Flutter invoke_service.dart)
# ══════════════════════════════════════════════════════════════════════════════

func _build_flux2_graph(prompt: String, width: int, height: int, ref_image_names: Array = []) -> Dictionary:
	var seed_value := randi() % 2147483647

	# Build ref_images metadata (matches Flutter's _buildRefImagesMetadata)
	var ref_images_meta: Array = []
	var valid_refs: Array = []
	for ref_name in ref_image_names:
		var rn: String = str(ref_name).strip_edges()
		if rn != "":
			valid_refs.append(rn)

	for i in range(valid_refs.size()):
		ref_images_meta.append({
			"id": "reference_image:%d" % i,
			"isEnabled": true,
			"config": {
				"type": "flux2_reference_image",
				"image": {
					"original": {
						"image": {
							"image_name": valid_refs[i],
							"width": 0,
							"height": 0,
						},
					},
				},
			},
		})

	var nodes := {
		"model_loader": {
			"id": "model_loader",
			"type": "flux2_klein_model_loader",
			"model": _main_model,
			"vae_model": _vae_model,
			"qwen3_encoder_model": _qwen3_encoder_model,
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
			"generation_mode": "flux2_txt2img",
			"positive_prompt": prompt,
			"seed": seed_value,
			"width": width,
			"height": height,
			"steps": 4,
			"scheduler": "euler",
			"model": _main_model,
			"vae": _vae_model,
			"qwen3_encoder": _qwen3_encoder_model,
			"ref_images": ref_images_meta,
		},
	}

	if _vae_model.is_empty():
		nodes["model_loader"].erase("vae_model")
	if _qwen3_encoder_model.is_empty():
		nodes["model_loader"].erase("qwen3_encoder_model")

	var edges := [
		# model_loader.transformer -> denoise.transformer
		{
			"source": {"node_id": "model_loader", "field": "transformer"},
			"destination": {"node_id": "denoise", "field": "transformer"},
		},
		# model_loader.vae -> denoise.vae
		{
			"source": {"node_id": "model_loader", "field": "vae"},
			"destination": {"node_id": "denoise", "field": "vae"},
		},
		# model_loader.qwen3_encoder -> positive_text.qwen3_encoder
		{
			"source": {"node_id": "model_loader", "field": "qwen3_encoder"},
			"destination": {"node_id": "positive_text", "field": "qwen3_encoder"},
		},
		# model_loader.max_seq_len -> positive_text.max_seq_len
		{
			"source": {"node_id": "model_loader", "field": "max_seq_len"},
			"destination": {"node_id": "positive_text", "field": "max_seq_len"},
		},
		# positive_text.conditioning -> denoise.positive_text_conditioning
		{
			"source": {"node_id": "positive_text", "field": "conditioning"},
			"destination": {"node_id": "denoise", "field": "positive_text_conditioning"},
		},
		# denoise.latents -> decode.latents
		{
			"source": {"node_id": "denoise", "field": "latents"},
			"destination": {"node_id": "decode", "field": "latents"},
		},
		# model_loader.vae -> decode.vae
		{
			"source": {"node_id": "model_loader", "field": "vae"},
			"destination": {"node_id": "decode", "field": "vae"},
		},
		# core_metadata.metadata -> decode.metadata
		{
			"source": {"node_id": "core_metadata", "field": "metadata"},
			"destination": {"node_id": "decode", "field": "metadata"},
		},
	]

	# Kontext reference images (face/context matching)
	if valid_refs.size() == 1:
		nodes["kontext_0"] = {
			"id": "kontext_0",
			"type": "flux_kontext",
			"image": {"image_name": valid_refs[0]},
		}
		edges.append({
			"source": {"node_id": "kontext_0", "field": "kontext_cond"},
			"destination": {"node_id": "denoise", "field": "kontext_conditioning"},
		})
	elif valid_refs.size() > 1:
		for i in range(valid_refs.size()):
			var kontext_id := "kontext_%d" % i
			var collect_id := "kontext_collect_%d" % i
			nodes[kontext_id] = {
				"id": kontext_id,
				"type": "flux_kontext",
				"image": {"image_name": valid_refs[i]},
			}
			nodes[collect_id] = {"id": collect_id, "type": "collect"}
			edges.append({
				"source": {"node_id": kontext_id, "field": "kontext_cond"},
				"destination": {"node_id": collect_id, "field": "item"},
			})
			if i > 0:
				edges.append({
					"source": {"node_id": "kontext_collect_%d" % (i - 1), "field": "collection"},
					"destination": {"node_id": collect_id, "field": "collection"},
				})
		edges.append({
			"source": {"node_id": "kontext_collect_%d" % (valid_refs.size() - 1), "field": "collection"},
			"destination": {"node_id": "denoise", "field": "kontext_conditioning"},
		})

	return {
		"id": "flux2_invoker",
		"nodes": nodes,
		"edges": edges,
	}


# ══════════════════════════════════════════════════════════════════════════════
# Batch polling
# ══════════════════════════════════════════════════════════════════════════════

func _poll_batch(batch_id: String) -> bool:
	var url := "%s/api/v1/queue/default/b/%s/status" % [GameState.invoke_url.rstrip("/"), batch_id]
	var max_attempts := 300
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
			await get_tree().create_timer(2.0).timeout
			attempts += 1
			continue

		var json := JSON.new()
		if json.parse(body.get_string_from_utf8()) != OK:
			await get_tree().create_timer(1.0).timeout
			attempts += 1
			continue

		var data: Dictionary = json.data if json.data is Dictionary else {}

		# InvokeAI batch status uses integer counters
		var completed_count: int = int(data.get("completed", 0))
		var failed_count: int = int(data.get("failed", 0))
		var canceled_count: int = int(data.get("canceled", 0))
		var total_count: int = int(data.get("total", 1))

		if total_count > 0:
			generation_progress.emit(float(completed_count) / float(total_count) * 100.0)

		if completed_count > 0:
			print("InvokeService: batch %s completed" % batch_id)
			return true
		if failed_count > 0:
			var detail: String = str(data.get("error", data.get("error_message", "")))
			push_error("InvokeService: batch %s failed: %s" % [batch_id, detail])
			generation_failed.emit("Batch fallito: %s" % detail)
			return false
		if canceled_count > 0:
			push_error("InvokeService: batch %s canceled" % batch_id)
			return false

		await get_tree().create_timer(1.5).timeout
		attempts += 1

	push_error("InvokeService: polling timed out for batch %s" % batch_id)
	return false


# ══════════════════════════════════════════════════════════════════════════════
# Image retrieval
# ══════════════════════════════════════════════════════════════════════════════

## Find the generated image name by matching session_id from the batch queue item.
## Mirrors Flutter's _imageNameFromBatch.
func _image_name_from_batch(batch_id: String) -> String:
	var base := GameState.invoke_url.rstrip("/")

	# Step 1: find session_id for this batch
	var session_id := ""
	var ids_url := "%s/api/v1/queue/default/item_ids?order_dir=DESC" % base
	var err := _poll_http.request(ids_url)
	if err != OK:
		return ""
	var ids_resp: Array = await _poll_http.request_completed
	if ids_resp[0] != HTTPRequest.RESULT_SUCCESS or ids_resp[1] < 200 or ids_resp[1] >= 300:
		return ""
	var ids_json := JSON.new()
	if ids_json.parse((ids_resp[3] as PackedByteArray).get_string_from_utf8()) != OK:
		return ""
	var ids_raw: Array = ids_json.data.get("item_ids", []) if ids_json.data is Dictionary else []

	for raw_id in ids_raw.slice(0, 40):
		var item_id: String = str(raw_id).strip_edges()
		if item_id.is_empty():
			continue
		var item_url := "%s/api/v1/queue/default/i/%s" % [base, item_id]
		err = _poll_http.request(item_url)
		if err != OK:
			continue
		var item_resp: Array = await _poll_http.request_completed
		if item_resp[0] != HTTPRequest.RESULT_SUCCESS or item_resp[1] < 200 or item_resp[1] >= 300:
			continue
		var item_json := JSON.new()
		if item_json.parse((item_resp[3] as PackedByteArray).get_string_from_utf8()) != OK:
			continue
		if not item_json.data is Dictionary:
			continue
		var item_batch: String = str(item_json.data.get("batch_id", "")).strip_edges()
		if item_batch != batch_id:
			continue
		session_id = str(item_json.data.get("session_id", "")).strip_edges()
		break

	if session_id.is_empty():
		print("InvokeService: could not find session_id for batch %s" % batch_id)
		return ""

	print("InvokeService: batch %s → session_id %s" % [batch_id, session_id])

	# Step 2: find image with that session_id
	var img_url := "%s/api/v1/images/?limit=50&offset=0&board_id=none&is_intermediate=false" % base
	err = _poll_http.request(img_url)
	if err != OK:
		return ""
	var img_resp: Array = await _poll_http.request_completed
	if img_resp[0] != HTTPRequest.RESULT_SUCCESS or img_resp[1] < 200 or img_resp[1] >= 300:
		return ""
	var img_json := JSON.new()
	if img_json.parse((img_resp[3] as PackedByteArray).get_string_from_utf8()) != OK:
		return ""
	var items: Array = []
	if img_json.data is Dictionary:
		items = img_json.data.get("items", [])
	for item in items:
		if not item is Dictionary:
			continue
		if str(item.get("session_id", "")).strip_edges() == session_id:
			var found_name: String = str(item.get("image_name", "")).strip_edges()
			if found_name != "":
				print("InvokeService: found image '%s' for session %s" % [found_name, session_id])
				return found_name
	return ""


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
		var err_body := response_body.get_string_from_utf8()
		push_error("InvokeService: HTTP %d – %s" % [http_code, err_body.left(500)])
		generation_failed.emit("HTTP %d: %s" % [http_code, err_body.left(200)])
		return {}

	var json := JSON.new()
	var parse_err := json.parse(response_body.get_string_from_utf8())
	if parse_err != OK:
		push_error("InvokeService: JSON parse error – %s" % json.get_error_message())
		return {}

	return json.data if json.data is Dictionary else {}
