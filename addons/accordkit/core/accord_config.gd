class_name AccordConfig extends RefCounted

const API_VERSION := "v1"
const API_BASE_PATH := "/api/" + API_VERSION
const DEFAULT_BASE_URL := "http://localhost:3000"
const DEFAULT_GATEWAY_URL := "ws://localhost:3000/ws"
const DEFAULT_CDN_URL := "http://localhost:3000/cdn"

const USER_AGENT := "AccordKit (GDScript, 2.0.0)"
const CLIENT_VERSION := "2.0.0"

const HEARTBEAT_INTERVAL_DEFAULT := 45000

var base_url: String = DEFAULT_BASE_URL
var gateway_url: String = DEFAULT_GATEWAY_URL
var cdn_url: String = DEFAULT_CDN_URL

func api_url() -> String:
	return base_url + API_BASE_PATH

func gateway_connect_url() -> String:
	return gateway_url + "?v=1&encoding=json"
