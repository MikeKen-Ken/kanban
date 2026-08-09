#ifndef RUNNER_WINDOW_PREFERENCES_WINDOW_SIZE_PREFERENCES_H_
#define RUNNER_WINDOW_PREFERENCES_WINDOW_SIZE_PREFERENCES_H_

#include <windows.h>

#include <algorithm>

#include <flutter_windows.h>

namespace window_preferences {

struct WindowSize {
  unsigned int width;
  unsigned int height;
};

namespace internal {

constexpr const wchar_t kWindowPreferencesRegKey[] =
    L"Software\\Kanban\\Window";
constexpr const wchar_t kWindowWidthRegValue[] = L"Width";
constexpr const wchar_t kWindowHeightRegValue[] = L"Height";

constexpr unsigned int kMinimumWindowWidth = 640;
constexpr unsigned int kMinimumWindowHeight = 480;
constexpr unsigned int kMaximumStoredDimension = 16384;

inline bool ReadDimension(const wchar_t* name, unsigned int* value) {
  DWORD stored_value = 0;
  DWORD stored_value_size = sizeof(stored_value);
  const LSTATUS result = RegGetValue(
      HKEY_CURRENT_USER, kWindowPreferencesRegKey, name, RRF_RT_REG_DWORD,
      nullptr, &stored_value, &stored_value_size);
  if (result != ERROR_SUCCESS || stored_value < 1) {
    return false;
  }
  *value = stored_value;
  return true;
}

inline bool IsValidStoredSize(const WindowSize& size) {
  return size.width >= kMinimumWindowWidth &&
         size.height >= kMinimumWindowHeight &&
         size.width <= kMaximumStoredDimension &&
         size.height <= kMaximumStoredDimension;
}

inline WindowSize ClampToWorkArea(WindowSize size, POINT origin) {
  const HMONITOR monitor =
      MonitorFromPoint(origin, MONITOR_DEFAULTTONEAREST);
  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(monitor_info);
  if (!GetMonitorInfo(monitor, &monitor_info)) {
    return size;
  }

  const UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  if (dpi == 0) {
    return size;
  }

  const LONG work_area_width =
      monitor_info.rcWork.right - monitor_info.rcWork.left;
  const LONG work_area_height =
      monitor_info.rcWork.bottom - monitor_info.rcWork.top;
  const auto logical_work_area_width = static_cast<unsigned int>(
      std::max<LONG>(1, work_area_width) * 96 / dpi);
  const auto logical_work_area_height = static_cast<unsigned int>(
      std::max<LONG>(1, work_area_height) * 96 / dpi);

  size.width = std::min(size.width, logical_work_area_width);
  size.height = std::min(size.height, logical_work_area_height);
  return size;
}

inline void WriteDimension(HKEY key, const wchar_t* name,
                           unsigned int value) {
  const DWORD stored_value = value;
  RegSetValueEx(key, name, 0, REG_DWORD,
                reinterpret_cast<const BYTE*>(&stored_value),
                sizeof(stored_value));
}

}  // namespace internal

// 读取本机保存的窗口尺寸，并根据当前显示器工作区生成安全的启动尺寸。
inline WindowSize LoadWindowSize(WindowSize default_size, POINT origin) {
  WindowSize stored_size{};
  if (!internal::ReadDimension(internal::kWindowWidthRegValue,
                               &stored_size.width) ||
      !internal::ReadDimension(internal::kWindowHeightRegValue,
                               &stored_size.height) ||
      !internal::IsValidStoredSize(stored_size)) {
    stored_size = default_size;
  }
  return internal::ClampToWorkArea(stored_size, origin);
}

// 保存窗口的正常（非最小化、非最大化）尺寸；写入失败时保持静默回退。
inline void SaveWindowSize(HWND window) {
  if (window == nullptr) {
    return;
  }

  WINDOWPLACEMENT placement{};
  placement.length = sizeof(placement);
  if (!GetWindowPlacement(window, &placement)) {
    return;
  }

  const RECT& bounds = placement.rcNormalPosition;
  const LONG physical_width = bounds.right - bounds.left;
  const LONG physical_height = bounds.bottom - bounds.top;
  const HMONITOR monitor = MonitorFromRect(&bounds, MONITOR_DEFAULTTONEAREST);
  const UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  if (physical_width <= 0 || physical_height <= 0 || dpi == 0) {
    return;
  }

  const WindowSize logical_size{
      static_cast<unsigned int>(physical_width * 96 / dpi),
      static_cast<unsigned int>(physical_height * 96 / dpi),
  };
  if (!internal::IsValidStoredSize(logical_size)) {
    return;
  }

  HKEY key = nullptr;
  if (RegCreateKeyEx(HKEY_CURRENT_USER,
                     internal::kWindowPreferencesRegKey, 0, nullptr,
                     REG_OPTION_NON_VOLATILE, KEY_SET_VALUE, nullptr, &key,
                     nullptr) != ERROR_SUCCESS) {
    return;
  }
  internal::WriteDimension(key, internal::kWindowWidthRegValue,
                           logical_size.width);
  internal::WriteDimension(key, internal::kWindowHeightRegValue,
                           logical_size.height);
  RegCloseKey(key);
}

}  // namespace window_preferences

#endif  // RUNNER_WINDOW_PREFERENCES_WINDOW_SIZE_PREFERENCES_H_
