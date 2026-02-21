class_name MultipartForm
extends RefCounted

## Builds multipart/form-data request bodies for file uploads and mixed
## payloads. Each part is stored internally and assembled by build() into
## the final byte array suitable for an HTTP request body.

var _boundary: String = ""
var _parts: Array = []


func _init() -> void:
	_boundary = "----AccordForm" + str(randi())


## Adds a plain text field part.
func add_field(name: String, value: String) -> void:
	var part := PackedByteArray()
	var header := "--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n" % [_boundary, name]
	part.append_array(header.to_utf8_buffer())
	part.append_array(value.to_utf8_buffer())
	part.append_array("\r\n".to_utf8_buffer())
	_parts.append(part)


## Adds a JSON field part. The data is serialized with JSON.stringify.
func add_json(name: String, data) -> void:
	var json_str := JSON.stringify(data)
	var part := PackedByteArray()
	var header := (
		"--%s\r\nContent-Disposition: form-data; name=\"%s\""
		+ "\r\nContent-Type: application/json\r\n\r\n"
	) % [_boundary, name]
	part.append_array(header.to_utf8_buffer())
	part.append_array(json_str.to_utf8_buffer())
	part.append_array("\r\n".to_utf8_buffer())
	_parts.append(part)


## Adds a binary file part with the given filename and content type.
func add_file(
	name: String, filename: String, content: PackedByteArray,
	content_type: String = "application/octet-stream",
) -> void:
	var part := PackedByteArray()
	var header := (
		"--%s\r\nContent-Disposition: form-data; name=\"%s\""
		+ "; filename=\"%s\"\r\nContent-Type: %s\r\n\r\n"
	) % [_boundary, name, filename, content_type]
	part.append_array(header.to_utf8_buffer())
	part.append_array(content)
	part.append_array("\r\n".to_utf8_buffer())
	_parts.append(part)


## Returns the Content-Type header value including the boundary.
func get_content_type() -> String:
	return "multipart/form-data; boundary=" + _boundary


## Assembles all parts into the final multipart body as a PackedByteArray.
func build() -> PackedByteArray:
	var result := PackedByteArray()
	for part in _parts:
		result.append_array(part)
	var closing := "--%s--\r\n" % _boundary
	result.append_array(closing.to_utf8_buffer())
	return result
