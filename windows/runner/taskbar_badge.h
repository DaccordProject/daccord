#ifndef RUNNER_TASKBAR_BADGE_H_
#define RUNNER_TASKBAR_BADGE_H_

#include <flutter/flutter_engine.h>
#include <windows.h>

// Unread taskbar badge for Windows, drawn as a taskbar overlay icon (see
// taskbar_badge.cpp). Registers the `com.daccord.app/taskbar_badge` method
// channel on |engine|; |window| is the top-level HWND whose taskbar button
// carries the overlay.
void TaskbarBadgeRegister(flutter::FlutterEngine* engine, HWND window);

// The shell's "TaskbarButtonCreated" message, registered on first use. The
// window procedure must forward it to TaskbarBadgeReapply().
UINT TaskbarBadgeButtonCreatedMessage();

// Re-applies the last badge state. The taskbar drops overlay icons when it
// recreates a window's button (explorer.exe restart, first show), so this is
// how the badge survives.
void TaskbarBadgeReapply();

#endif  // RUNNER_TASKBAR_BADGE_H_
