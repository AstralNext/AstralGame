#include "single_instance.h"

#include <windows.h>

#include <string>

namespace {

constexpr wchar_t kMutexName[] =
    L"Local\\AstralNext.AstralGame.SingleInstance.v1";
constexpr wchar_t kWindowTitle[] = L"astral_game";
constexpr wchar_t kPendingUriFile[] = L"astral_game_pending_uri.txt";

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

bool LooksLikeJoinUri(const wchar_t* arg) {
  if (arg == nullptr || arg[0] == L'\0') {
    return false;
  }
  if (_wcsnicmp(arg, L"astralgame:", 11) == 0) {
    return true;
  }
  if (_wcsnicmp(arg, L"astral:", 7) == 0) {
    return true;
  }
  if (_wcsnicmp(arg, L"https:", 6) == 0) {
    return true;
  }
  if (_wcsnicmp(arg, L"http:", 5) == 0) {
    return true;
  }
  return false;
}

void WritePendingUri(const wchar_t* uri) {
  wchar_t tmp[MAX_PATH];
  const DWORD n = GetTempPathW(MAX_PATH, tmp);
  if (n == 0 || n >= MAX_PATH) {
    return;
  }

  std::wstring path(tmp);
  path += kPendingUriFile;

  const int utf8_len =
      WideCharToMultiByte(CP_UTF8, 0, uri, -1, nullptr, 0, nullptr, nullptr);
  if (utf8_len <= 1) {
    return;
  }
  std::string utf8(static_cast<size_t>(utf8_len - 1), '\0');
  WideCharToMultiByte(CP_UTF8, 0, uri, -1, utf8.data(), utf8_len, nullptr,
                      nullptr);

  HANDLE file = CreateFileW(path.c_str(), GENERIC_WRITE, FILE_SHARE_READ,
                            nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL,
                            nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    return;
  }
  DWORD written = 0;
  WriteFile(file, utf8.data(), static_cast<DWORD>(utf8.size()), &written,
            nullptr);
  CloseHandle(file);
}

void ForwardCommandLineUriIfAny() {
  int argc = 0;
  wchar_t** argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return;
  }
  for (int i = 1; i < argc; i++) {
    if (LooksLikeJoinUri(argv[i])) {
      WritePendingUri(argv[i]);
      break;
    }
  }
  LocalFree(argv);
}

}  // namespace

bool EnsureSingleInstance() {
  HANDLE mutex = CreateMutexW(nullptr, TRUE, kMutexName);
  if (mutex == nullptr) {
    return true;
  }

  if (GetLastError() == ERROR_ALREADY_EXISTS) {
    CloseHandle(mutex);
    ForwardCommandLineUriIfAny();
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
