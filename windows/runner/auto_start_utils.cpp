// auto_start_utils.cpp - Windows launch-on-startup registry utilities

#include "auto_start_utils.h"

#include <windows.h>
#include <string>

namespace {

constexpr wchar_t kRunKeyPath[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
constexpr wchar_t kValueName[] = L"Kazumi";

bool OpenRunKey(REGSAM access, HKEY* out_key) {
  return RegOpenKeyExW(HKEY_CURRENT_USER, kRunKeyPath, 0, access,
                       out_key) == ERROR_SUCCESS;
}

}  // namespace

bool AutoStartUtils::SetLaunchOnStartup(bool enable) {
  HKEY key = nullptr;
  if (!OpenRunKey(KEY_SET_VALUE, &key)) {
    return false;
  }
  bool success;
  if (enable) {
    wchar_t exe_path[MAX_PATH];
    if (GetModuleFileNameW(nullptr, exe_path, MAX_PATH) == 0) {
      RegCloseKey(key);
      return false;
    }
    // Quote the path so entries with spaces survive.
    std::wstring command = L"\"" + std::wstring(exe_path) + L"\"";
    success = RegSetValueExW(key, kValueName, 0, REG_SZ,
                             reinterpret_cast<const BYTE*>(command.c_str()),
                             static_cast<DWORD>((command.size() + 1) *
                                                sizeof(wchar_t))) ==
              ERROR_SUCCESS;
  } else {
    // Removing a missing value still counts as success.
    const LSTATUS status = RegDeleteValueW(key, kValueName);
    success = status == ERROR_SUCCESS || status == ERROR_FILE_NOT_FOUND;
  }
  RegCloseKey(key);
  return success;
}

bool AutoStartUtils::IsLaunchOnStartupEnabled() {
  HKEY key = nullptr;
  if (!OpenRunKey(KEY_QUERY_VALUE, &key)) {
    return false;
  }
  DWORD type = 0;
  const bool exists =
      RegQueryValueExW(key, kValueName, nullptr, &type, nullptr, nullptr) ==
      ERROR_SUCCESS;
  RegCloseKey(key);
  return exists;
}
