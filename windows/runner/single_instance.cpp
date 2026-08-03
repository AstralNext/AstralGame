#include "single_instance.h"

#include <windows.h>

namespace {

constexpr wchar_t kMutexName[] =
    L"Local\\AstralNext.AstralGame.SingleInstance.v1";
constexpr wchar_t kWindowTitle[] = L"astral_game";

BOOL CALLBACK BringExistingWindowToFront(HWND hwnd, LPARAM) {
  if (!IsWindowVisible(hwnd)) {
    return TRUE;
  }

  wchar_t title[256];
  if (GetWindowTextW(hwnd, title, 256) == 0 ||
      wcscmp(title, kWindowTitle) != 0) {
    return TRUE;
  }

  DWORD window_pid = 0;
  GetWindowThreadProcessId(hwnd, &window_pid);
  if (window_pid == GetCurrentProcessId()) {
    return TRUE;
  }

  AllowSetForegroundWindow(window_pid);

  if (IsIconic(hwnd)) {
    ShowWindow(hwnd, SW_RESTORE);
  } else {
    ShowWindow(hwnd, SW_SHOW);
  }

  SetForegroundWindow(hwnd);
  return FALSE;
}

}  // namespace

bool EnsureSingleInstance() {
  HANDLE mutex =
      CreateMutexW(nullptr, TRUE, kMutexName);
  if (mutex == nullptr) {
    return true;
  }

  if (GetLastError() == ERROR_ALREADY_EXISTS) {
    CloseHandle(mutex);
    HWND existing = FindWindowW(nullptr, kWindowTitle);
    if (existing != nullptr) {
      BringExistingWindowToFront(existing, 0);
    } else {
      EnumWindows(BringExistingWindowToFront, 0);
    }
    return false;
  }

  return true;
}
