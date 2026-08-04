#include "taskbar_badge.h"

#include <gio/gio.h>

// Taskbar/dock unread badge for Linux.
//
// There is no cross-desktop badge API, but the de-facto standard is Ubuntu's
// Unity Launcher API: an unsolicited `Update` signal on the session bus that
// launchers listen for. GNOME's Dash-to-Dock, KDE Plasma's task manager,
// Cairo/Plank/Latte docks and elementary's Dock all implement it, so a single
// signal covers every mainstream desktop. Nothing implements it as a *service*,
// which is why this emits the signal blind rather than calling a method: if no
// launcher is listening the signal is simply dropped.
//
// The desktop-file id has to match the one we install (see dist/build-deb.sh →
// /usr/share/applications/daccord.desktop); launchers key the badge off it and
// silently ignore ids they can't resolve — which is also why the badge does
// nothing under `flutter run` from a source tree, where no .desktop file is
// installed.

static constexpr char kChannelName[] = "com.daccord.app/taskbar_badge";
static constexpr char kLauncherPath[] = "/com/canonical/Unity/LauncherEntry";
static constexpr char kLauncherInterface[] = "com.canonical.Unity.LauncherEntry";
static constexpr char kAppUri[] = "application://daccord.desktop";

// Session bus, opened lazily and kept for the process lifetime (the badge is
// updated on every incoming message, so reconnecting per update would be
// wasteful). Null when the bus is unavailable — e.g. a headless session.
static GDBusConnection* session_bus = nullptr;
static gboolean session_bus_failed = FALSE;

static GDBusConnection* get_session_bus() {
  if (session_bus != nullptr || session_bus_failed) {
    return session_bus;
  }
  g_autoptr(GError) error = nullptr;
  session_bus = g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, &error);
  if (session_bus == nullptr) {
    // Don't retry on every badge update; without a session bus there will never
    // be a launcher to talk to.
    session_bus_failed = TRUE;
    g_warning("taskbar badge: no session bus: %s",
              error != nullptr ? error->message : "unknown error");
  }
  return session_bus;
}

// Emits `LauncherEntry.Update` with the count fields. `count` is the number a
// launcher renders; `count_visible` toggles the badge itself, so clearing is
// count_visible = FALSE (a launcher keeps the last value it was told otherwise).
static void emit_launcher_update(gint64 count, gboolean count_visible) {
  GDBusConnection* bus = get_session_bus();
  if (bus == nullptr) {
    return;
  }

  GVariantBuilder builder;
  g_variant_builder_init(&builder, G_VARIANT_TYPE("a{sv}"));
  g_variant_builder_add(&builder, "{sv}", "count", g_variant_new_int64(count));
  g_variant_builder_add(&builder, "{sv}", "count-visible",
                        g_variant_new_boolean(count_visible));

  g_autoptr(GError) error = nullptr;
  g_dbus_connection_emit_signal(
      bus, nullptr, kLauncherPath, kLauncherInterface, "Update",
      g_variant_new("(sa{sv})", kAppUri, &builder), &error);
  if (error != nullptr) {
    g_warning("taskbar badge: emit failed: %s", error->message);
  }
}

static void handle_method_call(FlMethodChannel* channel,
                               FlMethodCall* method_call,
                               gpointer user_data) {
  if (g_strcmp0(fl_method_call_get_name(method_call), "setBadge") != 0) {
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  gint64 count = 0;
  gboolean visible = FALSE;
  FlValue* args = fl_method_call_get_args(method_call);
  if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
    FlValue* count_value = fl_value_lookup_string(args, "count");
    if (count_value != nullptr &&
        fl_value_get_type(count_value) == FL_VALUE_TYPE_INT) {
      count = fl_value_get_int(count_value);
    }
    FlValue* visible_value = fl_value_lookup_string(args, "visible");
    if (visible_value != nullptr &&
        fl_value_get_type(visible_value) == FL_VALUE_TYPE_BOOL) {
      visible = fl_value_get_bool(visible_value) ? TRUE : FALSE;
    }
  }

  // Mentions → the number; unread without mentions → a visible badge with no
  // count (the API's closest thing to a dot; launchers that refuse to draw a
  // zero-count badge just show nothing, which is the honest degradation).
  emit_launcher_update(count > 0 ? count : 0, visible ? TRUE : FALSE);

  g_autoptr(FlMethodResponse) response =
      FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  fl_method_call_respond(method_call, response, nullptr);
}

void taskbar_badge_register(FlView* view) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  // Intentionally leaked: the channel must outlive this call and lives as long
  // as the engine does.
  FlMethodChannel* channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)), kChannelName,
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, handle_method_call,
                                            nullptr, nullptr);
}
