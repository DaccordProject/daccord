class_name EmojiCatalog
extends Resource

## Resource that stores the full emoji catalog as parallel packed arrays.
## Each index i represents one emoji: names[i], codepoints[i], categories[i].

@export var names: PackedStringArray
@export var codepoints: PackedStringArray
@export var categories: PackedInt32Array

## Category display names, indexed by EmojiData.Category enum value.
@export var category_names: PackedStringArray

## Category icon codepoints, indexed by EmojiData.Category enum value.
@export var category_icons: PackedStringArray

## Skin tone modifier codepoints (index 0 = none, 1-5 = tones).
@export var skin_tone_modifiers: PackedStringArray

## Emoji names that support skin tone modifiers.
@export var skin_tone_emoji: PackedStringArray
