#include "taskbar_badge.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <objidl.h>
// gdiplus.h requires objidl.h (IStream) and min/max; the runner builds with
// NOMINMAX, so provide the two names GDI+ headers expect.
#include <algorithm>
namespace Gdiplus {
using std::max;
using std::min;
}  // namespace Gdiplus
#include <gdiplus.h>
#include <shobjidl_core.h>
// Current SDKs define the pixel-format constants as macros (so they resolve
// unqualified); older ones declare them inside namespace Gdiplus.
#ifndef PixelFormat32bppARGB
using Gdiplus::PixelFormat32bppARGB;
#endif

#include <memory>
#include <string>

// Unread taskbar badge for Windows.
//
// Windows has no numeric badge API; the native idiom is ITaskbarList3::
// SetOverlayIcon, a small icon composited onto the corner of the taskbar
// button. So we draw the badge ourselves: a filled circle carrying the mention
// count, or a smaller plain dot when something is unread but unmentioned.
//
// This lives in the runner rather than a plugin because no maintained Flutter
// package wraps SetOverlayIcon, and the whole implementation is one COM
// interface plus a GDI+ draw.

namespace {

constexpr char kChannelName[] = "com.daccord.app/taskbar_badge";

// Past two digits the number stops being readable at 16px (and stops mattering).
constexpr int kMaxDisplayedCount = 9;

// Badge fill — the same alarm red the in-app mention badges use.
constexpr BYTE kBadgeR = 237;
constexpr BYTE kBadgeG = 66;
constexpr BYTE kBadgeB = 69;

HWND g_window = nullptr;
// Leaked on purpose: COM is uninitialised by wWinMain, so releasing this from a
// static destructor (which runs later) would touch a dead apartment.
ITaskbarList3* g_taskbar_list = nullptr;
bool g_taskbar_list_failed = false;
ULONG_PTR g_gdiplus_token = 0;
UINT g_button_created_message = 0;

int g_last_count = 0;
bool g_last_visible = false;

// Also leaked: both hold engine-owned pointers, and the engine is torn down in
// FlutterWindow::OnDestroy — before static destructors would run.
flutter::PluginRegistrarWindows* g_registrar = nullptr;
flutter::MethodChannel<flutter::EncodableValue>* g_channel = nullptr;

// Lazily creates the taskbar COM object. COM is already initialised on this
// (platform) thread by wWinMain.
bool EnsureTaskbarList() {
  if (g_taskbar_list != nullptr) {
    return true;
  }
  if (g_taskbar_list_failed || g_window == nullptr) {
    return false;
  }
  HRESULT hr = CoCreateInstance(CLSID_TaskbarList, nullptr, CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&g_taskbar_list));
  if (SUCCEEDED(hr)) {
    hr = g_taskbar_list->HrInit();
  }
  if (FAILED(hr)) {
    if (g_taskbar_list != nullptr) {
      g_taskbar_list->Release();
      g_taskbar_list = nullptr;
    }
    // Nothing transient can fix this (no shell / no taskbar), so stop trying.
    g_taskbar_list_failed = true;
    return false;
  }
  return true;
}

bool EnsureGdiplus() {
  if (g_gdiplus_token != 0) {
    return true;
  }
  Gdiplus::GdiplusStartupInput input;
  // Never shut down: the badge can be redrawn until the process exits, and the
  // OS reclaims this at exit anyway.
  return Gdiplus::GdiplusStartup(&g_gdiplus_token, &input, nullptr) ==
         Gdiplus::Ok;
}

// Draws the overlay: a filled circle with |text| centred in it, or — when
// |text| is empty — a smaller inset dot meaning "unread, no mentions".
// Returns nullptr on failure; the caller owns the icon.
HICON CreateBadgeIcon(const std::wstring& text) {
  if (!EnsureGdiplus()) {
    return nullptr;
  }
  // Overlays are composited at the small-icon size; ask the system so this
  // follows the DPI the process is running at.
  int size = GetSystemMetrics(SM_CXSMICON);
  if (size < 16) {
    size = 16;
  }
  const float extent = static_cast<float>(size);

  Gdiplus::Bitmap bitmap(size, size, PixelFormat32bppARGB);
  if (bitmap.GetLastStatus() != Gdiplus::Ok) {
    return nullptr;
  }
  Gdiplus::Graphics graphics(&bitmap);
  graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
  graphics.Clear(Gdiplus::Color(0, 0, 0, 0));

  Gdiplus::SolidBrush fill(Gdiplus::Color(255, kBadgeR, kBadgeG, kBadgeB));
  if (text.empty()) {
    const float inset = extent * 0.25f;
    graphics.FillEllipse(&fill, inset, inset, extent - 2 * inset,
                         extent - 2 * inset);
  } else {
    graphics.FillEllipse(&fill, 0.0f, 0.0f, extent - 1.0f, extent - 1.0f);

    Gdiplus::FontFamily family(L"Segoe UI");
    Gdiplus::Font font(
        family.GetLastStatus() == Gdiplus::Ok
            ? &family
            : Gdiplus::FontFamily::GenericSansSerif(),
        extent * 0.62f, Gdiplus::FontStyleBold, Gdiplus::UnitPixel);
    Gdiplus::SolidBrush text_brush(Gdiplus::Color(255, 255, 255, 255));
    Gdiplus::StringFormat format;
    format.SetAlignment(Gdiplus::StringAlignmentCenter);
    format.SetLineAlignment(Gdiplus::StringAlignmentCenter);
    graphics.SetTextRenderingHint(Gdiplus::TextRenderingHintAntiAlias);
    graphics.DrawString(text.c_str(), -1, &font,
                        Gdiplus::RectF(0.0f, 0.0f, extent, extent), &format,
                        &text_brush);
  }

  HICON icon = nullptr;
  if (bitmap.GetHICON(&icon) != Gdiplus::Ok) {
    return nullptr;
  }
  return icon;
}

void ApplyBadge(int count, bool visible) {
  g_last_count = count;
  g_last_visible = visible;
  if (!EnsureTaskbarList()) {
    return;
  }
  if (!visible) {
    g_taskbar_list->SetOverlayIcon(g_window, nullptr, nullptr);
    return;
  }

  std::wstring text;
  std::wstring description = L"Unread messages";
  if (count > 0) {
    text = count > kMaxDisplayedCount
               ? std::to_wstring(kMaxDisplayedCount) + L"+"
               : std::to_wstring(count);
    description = text + L" mentions";
  }

  HICON icon = CreateBadgeIcon(text);
  if (icon == nullptr) {
    return;
  }
  // The shell takes its own copy, so the icon is ours to free straight away.
  g_taskbar_list->SetOverlayIcon(g_window, icon, description.c_str());
  DestroyIcon(icon);
}

int ReadInt(const flutter::EncodableMap& map, const char* key) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) {
    return 0;
  }
  if (const auto* value = std::get_if<int32_t>(&it->second)) {
    return *value;
  }
  if (const auto* value = std::get_if<int64_t>(&it->second)) {
    return static_cast<int>(*value);
  }
  return 0;
}

bool ReadBool(const flutter::EncodableMap& map, const char* key) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) {
    return false;
  }
  const auto* value = std::get_if<bool>(&it->second);
  return value != nullptr && *value;
}

}  // namespace

void TaskbarBadgeRegister(flutter::FlutterEngine* engine, HWND window) {
  if (engine == nullptr || window == nullptr) {
    return;
  }
  g_window = window;
  g_registrar = new flutter::PluginRegistrarWindows(
      engine->GetRegistrarForPlugin("TaskbarBadge"));
  g_channel = new flutter::MethodChannel<flutter::EncodableValue>(
      g_registrar->messenger(), kChannelName,
      &flutter::StandardMethodCodec::GetInstance());
  g_channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() != "setBadge") {
          result->NotImplemented();
          return;
        }
        int count = 0;
        bool visible = false;
        if (const auto* args =
                std::get_if<flutter::EncodableMap>(call.arguments())) {
          count = ReadInt(*args, "count");
          visible = ReadBool(*args, "visible");
        }
        ApplyBadge(count, visible);
        result->Success();
      });
}

UINT TaskbarBadgeButtonCreatedMessage() {
  if (g_button_created_message == 0) {
    g_button_created_message = RegisterWindowMessage(L"TaskbarButtonCreated");
  }
  return g_button_created_message;
}

void TaskbarBadgeReapply() {
  if (!g_last_visible && g_last_count == 0) {
    return;
  }
  ApplyBadge(g_last_count, g_last_visible);
}
