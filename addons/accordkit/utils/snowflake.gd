class_name AccordSnowflake extends RefCounted

# Accord epoch: 2024-01-01T00:00:00Z in milliseconds
const EPOCH_MS := 1704067200000

static func decode_timestamp_ms(snowflake: String) -> int:
	if snowflake.is_empty():
		return 0
	var id := snowflake.to_int()
	return (id >> 22) + EPOCH_MS

static func decode_timestamp(snowflake: String) -> float:
	return decode_timestamp_ms(snowflake) / 1000.0

static func decode_to_datetime(snowflake: String) -> Dictionary:
	var unix_ms := decode_timestamp_ms(snowflake)
	return Time.get_datetime_dict_from_unix_time(unix_ms / 1000)

static func from_timestamp_ms(timestamp_ms: int) -> String:
	var id := (timestamp_ms - EPOCH_MS) << 22
	return str(id)

static func generate_nonce() -> String:
	var now_ms := int(Time.get_unix_time_from_system() * 1000)
	var id := ((now_ms - EPOCH_MS) << 22) | (randi() & 0x3FFFFF)
	return str(id)
