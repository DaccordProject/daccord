#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>

#include <app_links/app_links_plugin_c_api.h>

#include "flutter_window.h"
#include "utils.h"

namespace
{

  // Held for the life of the process; a second Daccord sees it and hands
  // over to the first instead of starting.
  constexpr const wchar_t kSingleInstanceMutex[] =
      L"Local\\DaccordSingleInstance";
  constexpr const wchar_t kRunnerWindowClass[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

  // The file name of the running executable (lower-case, no directory).
  std::wstring OwnExecutableName()
  {
    wchar_t path[MAX_PATH];
    DWORD length = ::GetModuleFileNameW(nullptr, path, MAX_PATH);
    std::wstring name(path, length);
    size_t slash = name.find_last_of(L"\\/");
    if (slash != std::wstring::npos)
      name = name.substr(slash + 1);
    for (auto &c : name)
      c = static_cast<wchar_t>(towlower(c));
    return name;
  }

  // Whether [hwnd] is a Flutter runner window of another Daccord process.
  // Matched on the executable name, not the title or the class alone: every
  // Flutter desktop app shares the class, and the title is the app's to
  // change.
  bool IsOtherDaccordWindow(HWND hwnd, const std::wstring &own_name)
  {
    wchar_t class_name[64];
    if (::GetClassNameW(hwnd, class_name, 64) == 0 ||
        wcscmp(class_name, kRunnerWindowClass) != 0)
      return false;
    DWORD pid = 0;
    ::GetWindowThreadProcessId(hwnd, &pid);
    if (pid == 0 || pid == ::GetCurrentProcessId())
      return false;
    HANDLE process =
        ::OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (process == nullptr)
      return false;
    wchar_t path[MAX_PATH];
    DWORD size = MAX_PATH;
    bool match = false;
    if (::QueryFullProcessImageNameW(process, 0, path, &size))
    {
      std::wstring name(path, size);
      size_t slash = name.find_last_of(L"\\/");
      if (slash != std::wstring::npos)
        name = name.substr(slash + 1);
      for (auto &c : name)
        c = static_cast<wchar_t>(towlower(c));
      match = name == own_name;
    }
    ::CloseHandle(process);
    return match;
  }

  struct FindContext
  {
    std::wstring own_name;
    HWND found = nullptr;
  };

  BOOL CALLBACK FindDaccordWindow(HWND hwnd, LPARAM lparam)
  {
    auto *context = reinterpret_cast<FindContext *>(lparam);
    if (!IsOtherDaccordWindow(hwnd, context->own_name))
      return TRUE;
    context->found = hwnd;
    return FALSE;
  }

  // Brings the running instance's window back (it may be hidden in the tray
  // or minimised) and forwards any daccord:// link from this command line.
  void HandOverToRunningInstance()
  {
    FindContext context{OwnExecutableName()};
    ::EnumWindows(FindDaccordWindow, reinterpret_cast<LPARAM>(&context));
    HWND hwnd = context.found;
    if (hwnd == nullptr)
      return;
    // app_links reads the link from this process's command line and posts it
    // to the window as WM_COPYDATA, where its plugin picks it up.
    SendAppLink(hwnd);
    WINDOWPLACEMENT placement = {sizeof(WINDOWPLACEMENT)};
    ::GetWindowPlacement(hwnd, &placement);
    ::ShowWindow(hwnd, placement.showCmd == SW_SHOWMAXIMIZED ? SW_SHOWMAXIMIZED
                       : placement.showCmd == SW_SHOWMINIMIZED
                           ? SW_RESTORE
                           : SW_SHOW);
    ::SetForegroundWindow(hwnd);
  }

} // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command)
{
  // One Daccord at a time. With the first instance hidden in the tray, a
  // second launch (the shortcut, a daccord:// link) opened a blank grey
  // window that waited forever on the first instance's locked data files.
  HANDLE single_instance = ::CreateMutexW(nullptr, TRUE, kSingleInstanceMutex);
  if (single_instance != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS)
  {
    HandOverToRunningInstance();
    ::CloseHandle(single_instance);
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent())
  {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Daccord", origin, size))
  {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0))
  {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (single_instance != nullptr)
    ::CloseHandle(single_instance);
  return EXIT_SUCCESS;
}
