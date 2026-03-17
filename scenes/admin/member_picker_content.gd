extends VBoxContainer

## Content layout for the member picker popup.
## Used by channel_permissions_dialog to select member overwrites.

@onready var search_input: LineEdit = $SearchInput
@onready var member_list: VBoxContainer = $Scroll/MemberList
