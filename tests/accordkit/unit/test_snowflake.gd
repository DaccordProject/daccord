extends GutTest


func test_decode_timestamp_ms_valid() -> void:
	# A snowflake with known timestamp bits
	# (timestamp_ms - EPOCH_MS) << 22 = snowflake
	var ts_ms := 1704067200000 + 1000  # 1 second after epoch
	var snowflake := str((ts_ms - AccordSnowflake.EPOCH_MS) << 22)
	var decoded := AccordSnowflake.decode_timestamp_ms(snowflake)
	assert_eq(decoded, ts_ms)


func test_decode_timestamp_ms_empty() -> void:
	assert_eq(AccordSnowflake.decode_timestamp_ms(""), 0)


func test_decode_timestamp_seconds() -> void:
	var ts_ms := AccordSnowflake.EPOCH_MS + 5000
	var snowflake := str((ts_ms - AccordSnowflake.EPOCH_MS) << 22)
	var decoded := AccordSnowflake.decode_timestamp(snowflake)
	assert_almost_eq(decoded, ts_ms / 1000.0, 0.001)


func test_from_timestamp_ms_inverse() -> void:
	var original_ts := AccordSnowflake.EPOCH_MS + 42000
	var snowflake := AccordSnowflake.from_timestamp_ms(original_ts)
	var decoded_ts := AccordSnowflake.decode_timestamp_ms(snowflake)
	assert_eq(decoded_ts, original_ts)


func test_from_timestamp_ms_epoch() -> void:
	var snowflake := AccordSnowflake.from_timestamp_ms(AccordSnowflake.EPOCH_MS)
	assert_eq(snowflake, "0")


func test_generate_nonce_uniqueness() -> void:
	var nonces := {}
	for i in range(100):
		var nonce := AccordSnowflake.generate_nonce()
		assert_false(nonces.has(nonce), "Nonce should be unique: %s" % nonce)
		nonces[nonce] = true


func test_generate_nonce_is_string() -> void:
	var nonce := AccordSnowflake.generate_nonce()
	assert_typeof(nonce, TYPE_STRING)
	assert_false(nonce.is_empty())


func test_decode_to_datetime() -> void:
	var ts_ms := AccordSnowflake.EPOCH_MS + 86400000  # 1 day after epoch = 2024-01-02
	var snowflake := str((ts_ms - AccordSnowflake.EPOCH_MS) << 22)
	var dt := AccordSnowflake.decode_to_datetime(snowflake)
	assert_eq(dt["year"], 2024)
	assert_eq(dt["month"], 1)
	assert_eq(dt["day"], 2)


func test_epoch_constant() -> void:
	# 2024-01-01T00:00:00Z in milliseconds
	assert_eq(AccordSnowflake.EPOCH_MS, 1704067200000)
