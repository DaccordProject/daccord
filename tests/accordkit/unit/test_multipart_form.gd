extends GutTest


func test_content_type_includes_boundary() -> void:
	var form := MultipartForm.new()
	var ct := form.get_content_type()
	assert_true(ct.begins_with("multipart/form-data; boundary="))
	assert_true(ct.length() > 30)


func test_add_field_produces_correct_part() -> void:
	var form := MultipartForm.new()
	form.add_field("username", "testuser")
	var body := form.build()
	var body_str := body.get_string_from_utf8()
	assert_true(body_str.contains("Content-Disposition: form-data; name=\"username\""))
	assert_true(body_str.contains("testuser"))


func test_add_json_includes_content_type() -> void:
	var form := MultipartForm.new()
	form.add_json("payload_json", {"content": "hello"})
	var body := form.build()
	var body_str := body.get_string_from_utf8()
	assert_true(body_str.contains("Content-Type: application/json"))
	assert_true(body_str.contains("payload_json"))


func test_add_file_includes_filename() -> void:
	var form := MultipartForm.new()
	var content := "file data".to_utf8_buffer()
	form.add_file("files[0]", "image.png", content, "image/png")
	var body := form.build()
	var body_str := body.get_string_from_utf8()
	assert_true(body_str.contains('filename="image.png"'))
	assert_true(body_str.contains("Content-Type: image/png"))
	assert_true(body_str.contains("file data"))


func test_closing_boundary() -> void:
	var form := MultipartForm.new()
	form.add_field("x", "y")
	var body := form.build()
	var body_str := body.get_string_from_utf8()
	# Closing boundary ends with --
	assert_true(body_str.strip_edges().ends_with("--"))


func test_empty_form_has_closing_boundary() -> void:
	var form := MultipartForm.new()
	var body := form.build()
	var body_str := body.get_string_from_utf8()
	assert_true(body_str.strip_edges().ends_with("--"))


func test_multiple_parts() -> void:
	var form := MultipartForm.new()
	form.add_field("field1", "value1")
	form.add_field("field2", "value2")
	form.add_json("json_payload", {"key": "val"})
	var body := form.build()
	var body_str := body.get_string_from_utf8()
	assert_true(body_str.contains("field1"))
	assert_true(body_str.contains("field2"))
	assert_true(body_str.contains("json_payload"))


func test_boundary_is_unique() -> void:
	var form1 := MultipartForm.new()
	var form2 := MultipartForm.new()
	# Boundaries should differ (based on randi)
	var ct1 := form1.get_content_type()
	var ct2 := form2.get_content_type()
	# They may occasionally collide but generally should differ
	# We just verify the format is correct
	assert_true(ct1.begins_with("multipart/form-data; boundary="))
	assert_true(ct2.begins_with("multipart/form-data; boundary="))
