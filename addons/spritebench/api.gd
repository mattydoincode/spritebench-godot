@tool
extends Node

const Credentials := preload("credentials.gd")

var _http: HTTPRequest


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.use_threads = true
	_http.timeout = 60.0
	add_child(_http)


func get_json(path: String) -> Dictionary:
	return await _request_json(HTTPClient.METHOD_GET, path, null)


func post_json(path: String, body: Dictionary) -> Dictionary:
	return await _request_json(HTTPClient.METHOD_POST, path, body)


func download(url: String) -> Dictionary:
	var resolved := resolve_url(url)
	_http.timeout = 0.0
	var response := await _perform(resolved, _headers(resolved), HTTPClient.METHOD_GET, "")
	_http.timeout = 60.0
	return response


func resolve_url(url: String) -> String:
	var trimmed := url.strip_edges()
	if trimmed.begins_with("http://") or trimmed.begins_with("https://"):
		return trimmed
	if not trimmed.begins_with("/"):
		trimmed = "/" + trimmed
	return Credentials.base_url() + trimmed


func _request_json(method: HTTPClient.Method, path: String, body: Variant) -> Dictionary:
	var url := resolve_url(path)
	var payload := ""
	if body != null:
		payload = JSON.stringify(body)
	var response := await _perform(url, _headers(url), method, payload)
	if not response.ok:
		return response
	var parsed: Variant = JSON.parse_string((response.bytes as PackedByteArray).get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		response.ok = false
		response.error = "expected a JSON object"
		return response
	response.data = parsed
	return response


func _headers(url: String) -> PackedStringArray:
	var headers := PackedStringArray([
		"Accept: application/json",
		"Content-Type: application/json",
		"User-Agent: SpriteBench-Godot/0.1.0",
	])
	if _same_origin(url):
		var token := Credentials.pat()
		if not token.is_empty():
			headers.append("Authorization: Bearer %s" % token)
	return headers


func _same_origin(url: String) -> bool:
	return url.begins_with(Credentials.base_url() + "/") or url == Credentials.base_url()


func _perform(
	url: String,
	headers: PackedStringArray,
	method: HTTPClient.Method,
	payload: String
) -> Dictionary:
	var response := {
		"ok": false,
		"status": 0,
		"data": {},
		"bytes": PackedByteArray(),
		"error": "",
	}
	var err := _http.request(url, headers, method, payload)
	if err != OK:
		response.error = "could not start request (%s)" % error_string(err)
		return response

	var completed: Array = await _http.request_completed
	var result: int = completed[0]
	var status: int = completed[1]
	var body: PackedByteArray = completed[3]
	response.status = status
	response.bytes = body

	if result != HTTPRequest.RESULT_SUCCESS:
		response.error = _result_message(result)
		return response

	if status < 200 or status >= 300:
		response.error = _http_error(status, body)
		return response

	response.ok = true
	return response


func _http_error(status: int, body: PackedByteArray) -> String:
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) == TYPE_DICTIONARY and parsed.has("error"):
		return "%s: %s" % [status, str(parsed.error)]
	return "HTTP %s" % status


func _result_message(result: int) -> String:
	match result:
		HTTPRequest.RESULT_CANT_CONNECT:
			return "could not connect"
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "could not resolve host"
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return "connection error"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "TLS handshake failed"
		HTTPRequest.RESULT_TIMEOUT:
			return "request timed out"
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
			return "too many redirects"
		_:
			return "request failed (%s)" % result
