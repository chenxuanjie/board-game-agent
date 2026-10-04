#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <string>

#include "flutter_window.h"
#include "utils.h"

namespace {
// app_links 7.x receives UTF-8, NUL-terminated WM_COPYDATA with this message id.
// A bounded send avoids hanging an OAuth callback on an unresponsive instance.
constexpr ULONG_PTR kAppLinkMessage = WM_USER + 2;
constexpr char kLoginPrefix[] = "org.dpdns.cznas.boardgame://auth/callback?";

struct ExistingInstance {
  std::wstring executable;
  HWND window = nullptr;
};

BOOL CALLBACK FindApplicationWindow(HWND window, LPARAM parameter) {
  auto* existing = reinterpret_cast<ExistingInstance*>(parameter);
  wchar_t class_name[128] = {};
  if (!GetClassNameW(window, class_name, 128) ||
      wcscmp(class_name, L"FLUTTER_RUNNER_WIN32_WINDOW") != 0) return TRUE;
  DWORD process_id = 0;
  GetWindowThreadProcessId(window, &process_id);
  if (process_id == GetCurrentProcessId()) return TRUE;
  HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, process_id);
  if (!process) return TRUE;
  wchar_t path[32768] = {};
  DWORD length = 32768;
  const bool same = QueryFullProcessImageNameW(process, 0, path, &length) &&
      _wcsicmp(path, existing->executable.c_str()) == 0;
  CloseHandle(process);
  if (!same) return TRUE;
  existing->window = window;
  return FALSE;
}

// Returns 0 when this is not a callback or no previous instance exists.
int ForwardLoginCallback(const std::vector<std::string>& arguments) {
  if (arguments.size() != 1 || arguments.front().rfind(kLoginPrefix, 0) != 0) return 0;
  const auto& link = arguments.front();
  if (link.size() > 8192 || link.find('#') != std::string::npos) return -1;
  wchar_t path[32768] = {};
  const DWORD path_length = GetModuleFileNameW(nullptr, path, 32768);
  if (!path_length || path_length >= 32768) return -1;
  ExistingInstance existing{path, nullptr};
  EnumWindows(FindApplicationWindow, reinterpret_cast<LPARAM>(&existing));
  if (!existing.window) return 0;
  COPYDATASTRUCT data = {};
  data.dwData = kAppLinkMessage;
  data.cbData = static_cast<DWORD>(link.size() + 1);
  data.lpData = const_cast<char*>(link.c_str());
  DWORD_PTR accepted = 0;
  if (!SendMessageTimeoutW(existing.window, WM_COPYDATA, 0,
      reinterpret_cast<LPARAM>(&data), SMTO_ABORTIFHUNG | SMTO_BLOCK,
      2000, &accepted) || accepted != 1) return -1;
  if (IsIconic(existing.window)) ShowWindow(existing.window, SW_RESTORE);
  SetForegroundWindow(existing.window);
  return 1;
}
}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  std::vector<std::string> command_line_arguments = GetCommandLineArguments();
  const int forwarded = ForwardLoginCallback(command_line_arguments);
  if (forwarded != 0) return forwarded > 0 ? EXIT_SUCCESS : EXIT_FAILURE;
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 800);
  if (!window.Create(L"board_game_agent", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
