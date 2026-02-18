extends FlowContainer

const ReactionPillScene := preload("res://scenes/messages/reaction_pill.tscn")

func setup(reactions: Array, channel_id: String = "", message_id: String = "") -> void:
	for child in get_children():
		child.queue_free()

	if reactions.is_empty():
		visible = false
		return

	visible = true
	for r in reactions:
		var pill: Button = ReactionPillScene.instantiate()
		add_child(pill)
		r["channel_id"] = channel_id
		r["message_id"] = message_id
		pill.setup(r)
