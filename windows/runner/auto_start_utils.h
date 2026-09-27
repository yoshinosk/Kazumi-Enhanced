#ifndef RUNNER_AUTO_START_UTILS_H_
#define RUNNER_AUTO_START_UTILS_H_

// Windows launch-on-startup helpers: manage the HKCU Run registry value.
class AutoStartUtils {
 public:
  // Register / unregister the current executable under the HKCU Run key.
  static bool SetLaunchOnStartup(bool enable);

  // Whether the Run value currently exists (regardless of the user's
  // enable/disable choice in Task Manager).
  static bool IsLaunchOnStartupEnabled();
};

#endif  // RUNNER_AUTO_START_UTILS_H_
