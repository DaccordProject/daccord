#ifndef RUNNER_TASKBAR_BADGE_H_
#define RUNNER_TASKBAR_BADGE_H_

#include <flutter_linux/flutter_linux.h>

// Registers the `com.daccord.app/taskbar_badge` method channel on |view|'s
// engine, backing it with the Unity Launcher API (see taskbar_badge.cc).
//
// Call once, after the FlView is created. The channel object is owned by the
// process and lives until exit.
void taskbar_badge_register(FlView* view);

#endif  // RUNNER_TASKBAR_BADGE_H_
