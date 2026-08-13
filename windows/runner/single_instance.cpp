#include "single_instance.h"

#include <windows.h>

namespace {

constexpr wchar_t kMutexName[] =
    L"Local\\AstralNext.AstralGame.SingleInstance.v1";

}  // namespace

bool EnsureSingleInstance() {
  HANDLE mutex = CreateMutexW(nullptr, TRUE, kMutexName);
  if (mutex == nullptr) {
    return true;
  }

  if (GetLastError() == ERROR_ALREADY_EXISTS) {
    CloseHandle(mutex);
    return false;
  }

  return true;
}
