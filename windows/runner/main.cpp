#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
#ifndef _DEBUG
  // One AlienShot per user session. A second launch — say the desktop
  // shortcut while it's already in the tray — asks the running copy to show
  // its window and exits, instead of adding a second tray icon that fights the
  // first over the global hotkey. Skipped in debug builds so `flutter run`
  // still works next to an installed copy. The handle is deliberately never
  // closed: the mutex has to live as long as this process.
  HANDLE instance_mutex = ::CreateMutexW(nullptr, FALSE, L"Local\\AlienWave.AlienShot");
  if (instance_mutex != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    HWND running = ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"AlienShot");
    if (running != nullptr) {
      DWORD running_pid = 0;
      ::GetWindowThreadProcessId(running, &running_pid);
      // This process was just started by the user, so it may pass on the
      // right to take the foreground; otherwise Windows keeps the running
      // copy's window behind whatever is active.
      ::AllowSetForegroundWindow(running_pid);
      ::PostMessageW(running, ::RegisterWindowMessageW(kActivateMessageName), 0, 0);
    }
    return EXIT_SUCCESS;
  }
#endif

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
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
  if (!window.Create(L"AlienShot", origin, size)) {
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
