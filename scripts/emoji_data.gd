class_name EmojiData

## Static emoji catalog for the emoji picker.
## Maps categories to arrays of {name, codepoint} entries.
## Codepoints reference Twemoji SVGs in theme/emoji/.
## Textures are lazy-loaded on first access to avoid loading ~340 SVGs at startup.

enum Category { SMILEYS, PEOPLE, NATURE, FOOD, ACTIVITIES, TRAVEL, OBJECTS, SYMBOLS, FLAGS }

const CATEGORY_NAMES := {
	Category.SMILEYS: "Smileys & Emotion",
	Category.PEOPLE: "People & Body",
	Category.NATURE: "Animals & Nature",
	Category.FOOD: "Food & Drink",
	Category.ACTIVITIES: "Activities",
	Category.TRAVEL: "Travel & Places",
	Category.OBJECTS: "Objects",
	Category.SYMBOLS: "Symbols",
	Category.FLAGS: "Flags",
}

const CATEGORY_ICONS := {
	Category.SMILEYS: "1f600",
	Category.PEOPLE: "1f44b",
	Category.NATURE: "1f436",
	Category.FOOD: "1f34e",
	Category.ACTIVITIES: "26bd",
	Category.TRAVEL: "1f697",
	Category.OBJECTS: "1f4a1",
	Category.SYMBOLS: "2764",
	Category.FLAGS: "1f1fa-1f1f8",
}

const CATALOG := {
	Category.SMILEYS: [
		{"name": "grinning_face", "codepoint": "1f600"},
		{"name": "grinning_big_eyes", "codepoint": "1f603"},
		{"name": "grinning_smiling_eyes", "codepoint": "1f604"},
		{"name": "beaming_face", "codepoint": "1f601"},
		{"name": "grinning_squinting", "codepoint": "1f606"},
		{"name": "grinning_sweat", "codepoint": "1f605"},
		{"name": "rofl", "codepoint": "1f923"},
		{"name": "joy", "codepoint": "1f602"},
		{"name": "slightly_smiling", "codepoint": "1f642"},
		{"name": "upside_down", "codepoint": "1f643"},
		{"name": "winking", "codepoint": "1f609"},
		{"name": "smiling_eyes", "codepoint": "1f60a"},
		{"name": "halo", "codepoint": "1f607"},
		{"name": "hearts_face", "codepoint": "1f970"},
		{"name": "heart_eyes", "codepoint": "1f60d"},
		{"name": "star_struck", "codepoint": "1f929"},
		{"name": "blowing_kiss", "codepoint": "1f618"},
		{"name": "kissing", "codepoint": "1f617"},
		{"name": "yum", "codepoint": "1f60b"},
		{"name": "tongue_out", "codepoint": "1f61b"},
		{"name": "wink_tongue", "codepoint": "1f61c"},
		{"name": "zany", "codepoint": "1f92a"},
		{"name": "shushing", "codepoint": "1f92b"},
		{"name": "thinking", "codepoint": "1f914"},
		{"name": "monocle", "codepoint": "1f9d0"},
		{"name": "nerd", "codepoint": "1f913"},
		{"name": "sunglasses", "codepoint": "1f60e"},
		{"name": "partying", "codepoint": "1f973"},
		{"name": "cowboy", "codepoint": "1f920"},
		{"name": "smirking", "codepoint": "1f60f"},
		{"name": "unamused", "codepoint": "1f612"},
		{"name": "rolling_eyes", "codepoint": "1f644"},
		{"name": "disappointed", "codepoint": "1f61e"},
		{"name": "worried", "codepoint": "1f61f"},
		{"name": "angry", "codepoint": "1f620"},
		{"name": "rage", "codepoint": "1f621"},
		{"name": "crying", "codepoint": "1f62d"},
		{"name": "pleading", "codepoint": "1f97a"},
		{"name": "fearful", "codepoint": "1f628"},
		{"name": "scream", "codepoint": "1f631"},
		{"name": "exploding_head", "codepoint": "1f92f"},
		{"name": "hushed", "codepoint": "1f62f"},
		{"name": "sleeping", "codepoint": "1f634"},
		{"name": "drooling", "codepoint": "1f924"},
		{"name": "nauseated", "codepoint": "1f922"},
		{"name": "sneezing", "codepoint": "1f927"},
		{"name": "hot_face", "codepoint": "1f975"},
		{"name": "cold_face", "codepoint": "1f976"},
		{"name": "yawning", "codepoint": "1f971"},
		{"name": "lying", "codepoint": "1f925"},
		{"name": "skull", "codepoint": "1f480"},
		{"name": "clown", "codepoint": "1f921"},
		{"name": "poop", "codepoint": "1f4a9"},
		{"name": "ghost", "codepoint": "1f47b"},
		{"name": "alien", "codepoint": "1f47d"},
		{"name": "robot", "codepoint": "1f916"},
	],
	Category.PEOPLE: [
		{"name": "wave", "codepoint": "1f44b"},
		{"name": "raised_back_of_hand", "codepoint": "1f91a"},
		{"name": "raised_hand", "codepoint": "270b"},
		{"name": "vulcan", "codepoint": "1f596"},
		{"name": "thumbs_up", "codepoint": "1f44d"},
		{"name": "thumbs_down", "codepoint": "1f44e"},
		{"name": "clap", "codepoint": "1f44f"},
		{"name": "pray", "codepoint": "1f64f"},
		{"name": "muscle", "codepoint": "1f4aa"},
		{"name": "handshake", "codepoint": "1f91d"},
		{"name": "victory", "codepoint": "270c"},
		{"name": "ok_hand", "codepoint": "1f44c"},
		{"name": "pinching", "codepoint": "1f90f"},
		{"name": "fist_bump", "codepoint": "1f44a"},
		{"name": "left_fist", "codepoint": "1f91b"},
		{"name": "right_fist", "codepoint": "1f91c"},
		{"name": "crossed_fingers", "codepoint": "1f91e"},
		{"name": "rock_on", "codepoint": "1f918"},
		{"name": "call_me", "codepoint": "1f919"},
		{"name": "point_left", "codepoint": "1f448"},
		{"name": "point_right", "codepoint": "1f449"},
		{"name": "point_up", "codepoint": "1f446"},
		{"name": "point_down", "codepoint": "1f447"},
		{"name": "middle_finger", "codepoint": "1f595"},
		{"name": "palms_up", "codepoint": "1f932"},
		{"name": "writing_hand", "codepoint": "270d"},
		{"name": "nail_polish", "codepoint": "1f485"},
		{"name": "selfie", "codepoint": "1f933"},
		{"name": "busts_in_silhouette", "codepoint": "1f465"},
	],
	Category.NATURE: [
		{"name": "dog_face", "codepoint": "1f436"},
		{"name": "cat_face", "codepoint": "1f431"},
		{"name": "mouse_face", "codepoint": "1f42d"},
		{"name": "hamster", "codepoint": "1f439"},
		{"name": "rabbit", "codepoint": "1f430"},
		{"name": "fox", "codepoint": "1f98a"},
		{"name": "bear", "codepoint": "1f43b"},
		{"name": "panda", "codepoint": "1f43c"},
		{"name": "koala", "codepoint": "1f428"},
		{"name": "tiger", "codepoint": "1f42f"},
		{"name": "lion", "codepoint": "1f981"},
		{"name": "cow", "codepoint": "1f42e"},
		{"name": "pig", "codepoint": "1f437"},
		{"name": "frog", "codepoint": "1f438"},
		{"name": "monkey_face", "codepoint": "1f435"},
		{"name": "penguin", "codepoint": "1f427"},
		{"name": "chicken", "codepoint": "1f414"},
		{"name": "eagle", "codepoint": "1f985"},
		{"name": "owl", "codepoint": "1f989"},
		{"name": "unicorn", "codepoint": "1f984"},
		{"name": "bee", "codepoint": "1f41d"},
		{"name": "butterfly", "codepoint": "1f98b"},
		{"name": "ladybug", "codepoint": "1f41e"},
		{"name": "snail", "codepoint": "1f40c"},
		{"name": "octopus", "codepoint": "1f419"},
		{"name": "dolphin", "codepoint": "1f42c"},
		{"name": "whale", "codepoint": "1f433"},
		{"name": "shark", "codepoint": "1f988"},
		{"name": "turtle", "codepoint": "1f422"},
		{"name": "snake", "codepoint": "1f40d"},
		{"name": "crocodile", "codepoint": "1f40a"},
		{"name": "sunflower", "codepoint": "1f33b"},
		{"name": "rose", "codepoint": "1f339"},
		{"name": "hibiscus", "codepoint": "1f33a"},
		{"name": "cherry_blossom", "codepoint": "1f338"},
		{"name": "four_leaf_clover", "codepoint": "1f340"},
		{"name": "evergreen_tree", "codepoint": "1f332"},
		{"name": "cactus", "codepoint": "1f335"},
		{"name": "mushroom", "codepoint": "1f344"},
		{"name": "fallen_leaf", "codepoint": "1f342"},
	],
	Category.FOOD: [
		{"name": "red_apple", "codepoint": "1f34e"},
		{"name": "orange", "codepoint": "1f34a"},
		{"name": "lemon", "codepoint": "1f34b"},
		{"name": "banana", "codepoint": "1f34c"},
		{"name": "watermelon", "codepoint": "1f349"},
		{"name": "grapes", "codepoint": "1f347"},
		{"name": "strawberry", "codepoint": "1f353"},
		{"name": "peach", "codepoint": "1f351"},
		{"name": "cherries", "codepoint": "1f352"},
		{"name": "pineapple", "codepoint": "1f34d"},
		{"name": "tomato", "codepoint": "1f345"},
		{"name": "avocado", "codepoint": "1f951"},
		{"name": "corn", "codepoint": "1f33d"},
		{"name": "cheese", "codepoint": "1f9c0"},
		{"name": "egg", "codepoint": "1f95a"},
		{"name": "bacon", "codepoint": "1f953"},
		{"name": "pancakes", "codepoint": "1f95e"},
		{"name": "hamburger", "codepoint": "1f354"},
		{"name": "pizza", "codepoint": "1f355"},
		{"name": "hot_dog", "codepoint": "1f32d"},
		{"name": "taco", "codepoint": "1f32e"},
		{"name": "burrito", "codepoint": "1f32f"},
		{"name": "fries", "codepoint": "1f35f"},
		{"name": "sushi", "codepoint": "1f363"},
		{"name": "ramen", "codepoint": "1f35c"},
		{"name": "ice_cream", "codepoint": "1f368"},
		{"name": "cake", "codepoint": "1f382"},
		{"name": "shortcake", "codepoint": "1f370"},
		{"name": "doughnut", "codepoint": "1f369"},
		{"name": "cookie", "codepoint": "1f36a"},
		{"name": "chocolate", "codepoint": "1f36b"},
		{"name": "candy", "codepoint": "1f36c"},
		{"name": "lollipop", "codepoint": "1f36d"},
		{"name": "popcorn", "codepoint": "1f37f"},
		{"name": "hot_beverage", "codepoint": "2615"},
		{"name": "tea", "codepoint": "1f375"},
		{"name": "beer", "codepoint": "1f37a"},
		{"name": "wine", "codepoint": "1f377"},
		{"name": "cocktail", "codepoint": "1f378"},
		{"name": "milk", "codepoint": "1f95b"},
	],
	Category.ACTIVITIES: [
		{"name": "soccer", "codepoint": "26bd"},
		{"name": "basketball", "codepoint": "1f3c0"},
		{"name": "football", "codepoint": "1f3c8"},
		{"name": "baseball", "codepoint": "26be"},
		{"name": "tennis", "codepoint": "1f3be"},
		{"name": "volleyball", "codepoint": "1f3d0"},
		{"name": "pool_8_ball", "codepoint": "1f3b1"},
		{"name": "bowling", "codepoint": "1f3b3"},
		{"name": "ice_hockey", "codepoint": "1f3d2"},
		{"name": "table_tennis", "codepoint": "1f3d3"},
		{"name": "badminton", "codepoint": "1f3f8"},
		{"name": "boxing_glove", "codepoint": "1f94a"},
		{"name": "direct_hit", "codepoint": "1f3af"},
		{"name": "trophy", "codepoint": "1f3c6"},
		{"name": "sports_medal", "codepoint": "1f3c5"},
		{"name": "game_die", "codepoint": "1f3b2"},
		{"name": "jigsaw", "codepoint": "1f9e9"},
		{"name": "video_game", "codepoint": "1f3ae"},
		{"name": "slot_machine", "codepoint": "1f3b0"},
		{"name": "artist_palette", "codepoint": "1f3a8"},
		{"name": "performing_arts", "codepoint": "1f3ad"},
		{"name": "musical_note", "codepoint": "1f3b5"},
		{"name": "musical_notes", "codepoint": "1f3b6"},
		{"name": "guitar", "codepoint": "1f3b8"},
		{"name": "piano", "codepoint": "1f3b9"},
		{"name": "saxophone", "codepoint": "1f3b7"},
		{"name": "trumpet", "codepoint": "1f3ba"},
		{"name": "violin", "codepoint": "1f3bb"},
		{"name": "drum", "codepoint": "1f941"},
		{"name": "microphone", "codepoint": "1f3a4"},
		{"name": "headphone", "codepoint": "1f3a7"},
		{"name": "clapper_board", "codepoint": "1f3ac"},
		{"name": "ticket", "codepoint": "1f3ab"},
		{"name": "fishing", "codepoint": "1f3a3"},
		{"name": "ferris_wheel", "codepoint": "1f3a1"},
		{"name": "roller_coaster", "codepoint": "1f3a2"},
	],
	Category.TRAVEL: [
		{"name": "car", "codepoint": "1f697"},
		{"name": "taxi", "codepoint": "1f695"},
		{"name": "bus", "codepoint": "1f68c"},
		{"name": "police_car", "codepoint": "1f693"},
		{"name": "ambulance", "codepoint": "1f691"},
		{"name": "fire_engine", "codepoint": "1f692"},
		{"name": "bicycle", "codepoint": "1f6b2"},
		{"name": "motorcycle", "codepoint": "1f3cd"},
		{"name": "train", "codepoint": "1f686"},
		{"name": "airplane", "codepoint": "2708"},
		{"name": "helicopter", "codepoint": "1f681"},
		{"name": "rocket", "codepoint": "1f680"},
		{"name": "flying_saucer", "codepoint": "1f6f8"},
		{"name": "sailboat", "codepoint": "26f5"},
		{"name": "ship", "codepoint": "1f6a2"},
		{"name": "anchor", "codepoint": "2693"},
		{"name": "house", "codepoint": "1f3e0"},
		{"name": "building_construction", "codepoint": "1f3d7"},
		{"name": "stadium", "codepoint": "1f3df"},
		{"name": "mountain", "codepoint": "26f0"},
		{"name": "volcano", "codepoint": "1f30b"},
		{"name": "beach", "codepoint": "1f3d6"},
		{"name": "tent", "codepoint": "26fa"},
		{"name": "earth_americas", "codepoint": "1f30e"},
		{"name": "earth_asia", "codepoint": "1f30f"},
		{"name": "star", "codepoint": "2b50"},
		{"name": "crescent_moon", "codepoint": "1f319"},
		{"name": "sun", "codepoint": "2600"},
		{"name": "rainbow", "codepoint": "1f308"},
		{"name": "ocean_wave", "codepoint": "1f30a"},
		{"name": "milky_way", "codepoint": "1f30c"},
		{"name": "comet", "codepoint": "2604"},
		{"name": "sunrise", "codepoint": "1f305"},
		{"name": "fireworks", "codepoint": "1f386"},
		{"name": "sparkler", "codepoint": "1f387"},
		{"name": "compass", "codepoint": "1f9ed"},
	],
	Category.OBJECTS: [
		{"name": "watch", "codepoint": "231a"},
		{"name": "alarm_clock", "codepoint": "23f0"},
		{"name": "hourglass", "codepoint": "231b"},
		{"name": "mobile_phone", "codepoint": "1f4f1"},
		{"name": "laptop", "codepoint": "1f4bb"},
		{"name": "keyboard", "codepoint": "2328"},
		{"name": "camera", "codepoint": "1f4f7"},
		{"name": "video_camera", "codepoint": "1f4f9"},
		{"name": "tv", "codepoint": "1f4fa"},
		{"name": "radio", "codepoint": "1f4fb"},
		{"name": "battery", "codepoint": "1f50b"},
		{"name": "electric_plug", "codepoint": "1f50c"},
		{"name": "light_bulb", "codepoint": "1f4a1"},
		{"name": "books", "codepoint": "1f4da"},
		{"name": "open_book", "codepoint": "1f4d6"},
		{"name": "newspaper", "codepoint": "1f4f0"},
		{"name": "pencil", "codepoint": "270f"},
		{"name": "memo", "codepoint": "1f4dd"},
		{"name": "paperclip", "codepoint": "1f4ce"},
		{"name": "pushpin", "codepoint": "1f4cc"},
		{"name": "scissors", "codepoint": "2702"},
		{"name": "wrench", "codepoint": "1f527"},
		{"name": "hammer", "codepoint": "1f528"},
		{"name": "magnifying_glass", "codepoint": "1f50d"},
		{"name": "locked", "codepoint": "1f512"},
		{"name": "key", "codepoint": "1f511"},
		{"name": "gift", "codepoint": "1f381"},
		{"name": "party_popper", "codepoint": "1f389"},
		{"name": "bell", "codepoint": "1f514"},
		{"name": "gem", "codepoint": "1f48e"},
		{"name": "crown", "codepoint": "1f451"},
		{"name": "ring", "codepoint": "1f48d"},
		{"name": "briefcase", "codepoint": "1f4bc"},
		{"name": "money_bag", "codepoint": "1f4b0"},
		{"name": "envelope", "codepoint": "2709"},
		{"name": "package", "codepoint": "1f4e6"},
		{"name": "pill", "codepoint": "1f48a"},
		{"name": "syringe", "codepoint": "1f489"},
		{"name": "credit_card", "codepoint": "1f4b3"},
		{"name": "megaphone", "codepoint": "1f4e3"},
		{"name": "speech_balloon", "codepoint": "1f4ac"},
		{"name": "left_speech_bubble", "codepoint": "1f5e8"},
		{"name": "wastebasket", "codepoint": "1f5d1"},
		{"name": "gear", "codepoint": "2699"},
		{"name": "clipboard", "codepoint": "1f4cb"},
	],
	Category.SYMBOLS: [
		{"name": "heart", "codepoint": "2764"},
		{"name": "orange_heart", "codepoint": "1f9e1"},
		{"name": "yellow_heart", "codepoint": "1f49b"},
		{"name": "green_heart", "codepoint": "1f49a"},
		{"name": "blue_heart", "codepoint": "1f499"},
		{"name": "purple_heart", "codepoint": "1f49c"},
		{"name": "black_heart", "codepoint": "1f5a4"},
		{"name": "white_heart", "codepoint": "1f90d"},
		{"name": "brown_heart", "codepoint": "1f90e"},
		{"name": "broken_heart", "codepoint": "1f494"},
		{"name": "two_hearts", "codepoint": "1f495"},
		{"name": "sparkling_heart", "codepoint": "1f496"},
		{"name": "growing_heart", "codepoint": "1f497"},
		{"name": "revolving_hearts", "codepoint": "1f49e"},
		{"name": "100", "codepoint": "1f4af"},
		{"name": "check_mark", "codepoint": "2705"},
		{"name": "cross_mark", "codepoint": "274c"},
		{"name": "exclamation", "codepoint": "2757"},
		{"name": "question", "codepoint": "2753"},
		{"name": "sparkles", "codepoint": "2728"},
		{"name": "eyes", "codepoint": "1f440"},
		{"name": "collision", "codepoint": "1f4a5"},
		{"name": "anger", "codepoint": "1f4a2"},
		{"name": "dizzy", "codepoint": "1f4ab"},
		{"name": "zzz", "codepoint": "1f4a4"},
		{"name": "fire", "codepoint": "1f525"},
		{"name": "warning", "codepoint": "26a0"},
		{"name": "no_entry", "codepoint": "26d4"},
		{"name": "prohibited", "codepoint": "1f6ab"},
		{"name": "recycle", "codepoint": "267b"},
		{"name": "infinity", "codepoint": "267e"},
		{"name": "peace", "codepoint": "262e"},
		{"name": "yin_yang", "codepoint": "262f"},
		{"name": "trident", "codepoint": "1f531"},
		{"name": "heavy_plus_sign", "codepoint": "2795"},
		{"name": "down_triangle", "codepoint": "1f53d"},
		{"name": "play_button", "codepoint": "25b6"},
		{"name": "left_hook_arrow", "codepoint": "21a9"},
	],
	Category.FLAGS: [
		{"name": "flag_us", "codepoint": "1f1fa-1f1f8"},
		{"name": "flag_gb", "codepoint": "1f1ec-1f1e7"},
		{"name": "flag_ca", "codepoint": "1f1e8-1f1e6"},
		{"name": "flag_au", "codepoint": "1f1e6-1f1fa"},
		{"name": "flag_de", "codepoint": "1f1e9-1f1ea"},
		{"name": "flag_fr", "codepoint": "1f1eb-1f1f7"},
		{"name": "flag_es", "codepoint": "1f1ea-1f1f8"},
		{"name": "flag_it", "codepoint": "1f1ee-1f1f9"},
		{"name": "flag_jp", "codepoint": "1f1ef-1f1f5"},
		{"name": "flag_kr", "codepoint": "1f1f0-1f1f7"},
		{"name": "flag_cn", "codepoint": "1f1e8-1f1f3"},
		{"name": "flag_in", "codepoint": "1f1ee-1f1f3"},
		{"name": "flag_br", "codepoint": "1f1e7-1f1f7"},
		{"name": "flag_mx", "codepoint": "1f1f2-1f1fd"},
		{"name": "flag_ru", "codepoint": "1f1f7-1f1fa"},
		{"name": "flag_nl", "codepoint": "1f1f3-1f1f1"},
		{"name": "flag_se", "codepoint": "1f1f8-1f1ea"},
		{"name": "flag_no", "codepoint": "1f1f3-1f1f4"},
		{"name": "flag_fi", "codepoint": "1f1eb-1f1ee"},
		{"name": "flag_dk", "codepoint": "1f1e9-1f1f0"},
		{"name": "flag_ie", "codepoint": "1f1ee-1f1ea"},
		{"name": "flag_pt", "codepoint": "1f1f5-1f1f9"},
		{"name": "flag_ch", "codepoint": "1f1e8-1f1ed"},
		{"name": "flag_be", "codepoint": "1f1e7-1f1ea"},
		{"name": "flag_at", "codepoint": "1f1e6-1f1f9"},
		{"name": "flag_pl", "codepoint": "1f1f5-1f1f1"},
		{"name": "flag_tr", "codepoint": "1f1f9-1f1f7"},
		{"name": "flag_ua", "codepoint": "1f1fa-1f1e6"},
		{"name": "flag_nz", "codepoint": "1f1f3-1f1ff"},
		{"name": "flag_ar", "codepoint": "1f1e6-1f1f7"},
		{"name": "flag_za", "codepoint": "1f1ff-1f1e6"},
		{"name": "flag_eg", "codepoint": "1f1ea-1f1ec"},
		{"name": "flag_ng", "codepoint": "1f1f3-1f1ec"},
		{"name": "flag_ke", "codepoint": "1f1f0-1f1ea"},
		{"name": "flag_th", "codepoint": "1f1f9-1f1ed"},
		{"name": "flag_vn", "codepoint": "1f1fb-1f1f3"},
		{"name": "flag_ph", "codepoint": "1f1f5-1f1ed"},
		{"name": "flag_id", "codepoint": "1f1ee-1f1e9"},
		{"name": "flag_my", "codepoint": "1f1f2-1f1fe"},
		{"name": "flag_sg", "codepoint": "1f1f8-1f1ec"},
		{"name": "flag_il", "codepoint": "1f1ee-1f1f1"},
		{"name": "flag_sa", "codepoint": "1f1f8-1f1e6"},
		{"name": "flag_ae", "codepoint": "1f1e6-1f1ea"},
		{"name": "flag_cl", "codepoint": "1f1e8-1f1f1"},
		{"name": "flag_co", "codepoint": "1f1e8-1f1f4"},
		{"name": "flag_pe", "codepoint": "1f1f5-1f1ea"},
		{"name": "flag_gr", "codepoint": "1f1ec-1f1f7"},
		{"name": "flag_cz", "codepoint": "1f1e8-1f1ff"},
		{"name": "flag_ro", "codepoint": "1f1f7-1f1f4"},
		{"name": "flag_hu", "codepoint": "1f1ed-1f1fa"},
	],
}

# Skin tone modifier codepoints (index matches Config value: 0=none, 1-5=tones)
const SKIN_TONE_MODIFIERS := ["", "1f3fb", "1f3fc", "1f3fd", "1f3fe", "1f3ff"]

# Emoji names that support skin tone modifiers
const SKIN_TONE_EMOJI: Array[String] = [
	"wave", "raised_back_of_hand", "raised_hand", "vulcan",
	"thumbs_up", "thumbs_down", "clap", "pray", "muscle",
	"victory", "ok_hand", "pinching", "fist_bump",
	"left_fist", "right_fist", "crossed_fingers", "rock_on",
	"call_me", "point_left", "point_right", "point_up", "point_down",
	"middle_finger", "palms_up", "writing_hand", "nail_polish", "selfie",
]

static var _name_lookup: Dictionary = {}
static var _texture_cache: Dictionary = {} # "emoji_name" -> Texture2D
static var _skin_tone_textures: Dictionary = {} # "codepoint" -> Texture2D

static func _build_name_lookup() -> void:
	if not _name_lookup.is_empty():
		return
	for cat_entries in CATALOG.values():
		for entry in cat_entries:
			_name_lookup[entry["name"]] = entry

static func get_all_for_category(category: Category) -> Array:
	return CATALOG.get(category, [])

static func get_by_name(emoji_name: String) -> Dictionary:
	_build_name_lookup()
	return _name_lookup.get(emoji_name, {})

## Returns true if the emoji supports skin tone variants.
static func supports_skin_tone(emoji_name: String) -> bool:
	return emoji_name in SKIN_TONE_EMOJI

## Returns the codepoint for the emoji with the given skin tone applied.
## If tone is 0 (default) or emoji doesn't support tones, returns the base codepoint.
static func get_codepoint_with_tone(emoji_name: String, tone: int) -> String:
	var entry := get_by_name(emoji_name)
	if entry.is_empty():
		return ""
	var base_cp: String = entry["codepoint"]
	if tone <= 0 or tone > 5 or not supports_skin_tone(emoji_name):
		return base_cp
	return base_cp + "-" + SKIN_TONE_MODIFIERS[tone]

## Returns the texture for the emoji, optionally with skin tone applied.
## Textures are lazily loaded on first access and cached.
static func get_texture(emoji_name: String, tone: int = 0) -> Texture2D:
	if tone > 0 and supports_skin_tone(emoji_name):
		var cp := get_codepoint_with_tone(emoji_name, tone)
		if _skin_tone_textures.has(cp):
			return _skin_tone_textures[cp]
		var path = "res://assets/theme/emoji/" + cp + ".svg"
		if ResourceLoader.exists(path):
			var tex: Texture2D = load(path)
			_skin_tone_textures[cp] = tex
			return tex
		# Fall through to base texture

	if _texture_cache.has(emoji_name):
		return _texture_cache[emoji_name]
	var entry := get_by_name(emoji_name)
	if entry.is_empty():
		return null
	var path = "res://assets/theme/emoji/" + entry["codepoint"] + ".svg"
	if ResourceLoader.exists(path):
		var tex: Texture2D = load(path)
		_texture_cache[emoji_name] = tex
		return tex
	return null

## Converts a hex codepoint (possibly multi-part like "1f1fa-1f1f8") to a
## Unicode character string.
static func codepoint_to_char(hex_codepoint: String) -> String:
	var result := ""
	for part in hex_codepoint.split("-"):
		result += char(part.hex_to_int())
	return result
