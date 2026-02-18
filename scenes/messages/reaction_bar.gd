extends FlowContainer

const ReactionPillScene := preload("res://scenes/messages/reaction_pill.tscn")

func setup(reactions: Array) -> void:
	for child in get_children():
		child.queue_free()

	if reactions.is_empty():
		visible = false
		return

	visible = true
	for r in reactions:
		var pill: Button = ReactionPillScene.instantiate()
		add_child(pill)
		pill.setup(r)
