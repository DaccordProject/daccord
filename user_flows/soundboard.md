# Soundboard

Priority: 37
Depends on: Voice Channels
Status: Complete

Users play short audio clips into voice channels via an in-voice SFX panel. Server provides full REST CRUD + play trigger with gateway events. Client-side playback via `SoundManager` (download, decode, cache, play on SFX bus). Permissions: `manage_soundboard` (CRUD) and `use_soundboard` (play).

## Key Files

| File | Role |
|------|------|
| `scenes/soundboard/soundboard_panel.gd` | In-voice trigger panel with search |
| `scenes/admin/soundboard_management_dialog.gd` | Admin dialog: upload, rename, volume, delete |
| `scenes/admin/sound_row.gd` | Individual sound row controls |
| `scenes/sidebar/voice_bar.gd` | SFX button that toggles soundboard panel |
| `scenes/sidebar/channels/banner.gd` | Banner dropdown with "Soundboard" menu item |
| `scripts/autoload/sound_manager.gd` | Audio download, decode, cache, playback on SFX bus |
| `scripts/autoload/app_state.gd` | `soundboard_updated`, `soundboard_played` signals |
| `scripts/client/client_admin.gd` | Soundboard CRUD wrappers |
| `scripts/client/client_gateway_events.gd` | Soundboard gateway event handlers |
| `scripts/client/client_models.gd` | `sound_to_dict()` converter |
| `addons/accordkit/models/sound.gd` | `AccordSound` model |
| `addons/accordkit/rest/endpoints/soundboard_api.gd` | REST class (list/fetch/create/update/delete/play) |
| `addons/accordkit/gateway/gateway_socket.gd` | Gateway dispatch for `soundboard.*` events |
