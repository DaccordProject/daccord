extends AcceptDialog

const SOUND_EVENTS := [
	{"name": "message_received", "label": "Message received (unfocused channel)"},
	{"name": "mention_received", "label": "Mention received"},
	{"name": "message_sent", "label": "Message sent"},
	{"name": "voice_join", "label": "Join voice channel"},
	{"name": "voice_leave", "label": "Leave voice channel"},
	{"name": "peer_join", "label": "Peer joins voice channel"},
	{"name": "peer_leave", "label": "Peer leaves voice channel"},
	{"name": "mute", "label": "Mute"},
	{"name": "unmute", "label": "Unmute"},
	{"name": "deafen", "label": "Deafen"},
	{"name": "undeafen", "label": "Undeafen"},
]

var _checkboxes: Dictionary = {} # sound_name -> CheckBox

@onready var volume_slider: HSlider = $VBox/VolumeRow/VolumeSlider
@onready var volume_label: Label = $VBox/VolumeRow/VolumeValue
@onready var checks_container: VBoxContainer = $VBox/ChecksContainer

func _ready() -> void:
	title = "Sound Settings"
	ok_button_text = "Apply"

	volume_slider.min_value = 0.0
	volume_slider.max_value = 1.0
	volume_slider.step = 0.05
	volume_slider.value = Config.get_sfx_volume()
	volume_slider.value_changed.connect(_on_volume_changed)
	_update_volume_label(volume_slider.value)

	for event in SOUND_EVENTS:
		var name: String = event["name"]
		var label: String = event["label"]
		var cb := CheckBox.new()
		cb.text = label
		cb.button_pressed = Config.is_sound_enabled(name)
		checks_container.add_child(cb)
		_checkboxes[name] = cb

	confirmed.connect(_on_confirmed)

func _on_volume_changed(value: float) -> void:
	_update_volume_label(value)

func _update_volume_label(value: float) -> void:
	volume_label.text = "%d%%" % int(value * 100)

func _on_confirmed() -> void:
	Config.set_sfx_volume(volume_slider.value)
	for event in SOUND_EVENTS:
		var name: String = event["name"]
		var cb: CheckBox = _checkboxes[name]
		Config.set_sound_enabled(name, cb.button_pressed)
