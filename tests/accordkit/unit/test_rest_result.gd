extends GutTest


func test_success_result() -> void:
	var result := RestResult.success(200, {"key": "value"})
	assert_true(result.ok)
	assert_eq(result.status_code, 200)
	assert_eq(result.data["key"], "value")
	assert_null(result.error)


func test_failure_result() -> void:
	var err := AccordError.from_dict({"code": "not_found", "message": "resource not found"})
	var result := RestResult.failure(404, err)
	assert_false(result.ok)
	assert_eq(result.status_code, 404)
	assert_null(result.data)
	assert_not_null(result.error)


func test_has_more_with_cursor() -> void:
	var result := RestResult.success(200, [], {"after": "123", "has_more": true})
	assert_true(result.has_more)


func test_has_more_without_cursor() -> void:
	var result := RestResult.success(200, [])
	assert_false(result.has_more)


func test_has_more_cursor_false() -> void:
	var result := RestResult.success(200, [], {"has_more": false})
	assert_false(result.has_more)


func test_null_data() -> void:
	var result := RestResult.success(204, null)
	assert_true(result.ok)
	assert_null(result.data)
	assert_eq(result.status_code, 204)


func test_success_with_array_data() -> void:
	var result := RestResult.success(200, [1, 2, 3])
	assert_true(result.ok)
	assert_eq(result.data.size(), 3)


func test_default_cursor_is_empty() -> void:
	var result := RestResult.success(200, {})
	assert_eq(result.cursor, {})
