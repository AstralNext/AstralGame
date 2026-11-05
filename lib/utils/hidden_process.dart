import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// 以「不弹控制台窗口」的方式启动一个子进程，并捕获 stdout / stderr。
///
/// Flutter 桌面端是 GUI 子系统进程。直接 [Process.run] 一个控制台程序
/// （reg.exe / sc.exe / w32tm.exe / auto_dns_binder.exe / astral_mono_inject.exe …）
/// 时，Windows 会为新进程分配一个控制台，表现为一闪而过的黑色 cmd 窗口。
/// Dart 没有暴露 `CreateProcess` 的 creation flags，所以这里用 FFI 调用
/// `CreateProcessW` 并传 `CREATE_NO_WINDOW`，同时用匿名管道取回输出。
///
/// 非 Windows 平台没有这个问题，直接退回 [Process.run]。
Future<ProcessResult> runHidden(String executable, List<String> arguments) {
  if (!Platform.isWindows) {
    return Process.run(executable, arguments);
  }
  return _runWindows(executable, arguments);
}

// ---------------------------------------------------------------------------
// Win32 常量与结构体
// ---------------------------------------------------------------------------

/// `CREATE_NO_WINDOW`：子进程不会分配控制台窗口。
const int _createNoWindow = 0x08000000;

/// `STARTF_USESTDHANDLES`：让子进程使用 [StartupInfo] 里的三个标准句柄。
const int _startfUseStdHandles = 0x00000100;

/// `HANDLE_FLAG_INHERIT`。
const int _handleFlagInherit = 0x00000001;

/// `WAIT_OBJECT_0`。
const int _waitObject0 = 0;

/// 管道读取缓冲大小。
const int _readChunk = 4096;

/// 轮询进程状态 / 收数据的间隔。
const Duration _pollInterval = Duration(milliseconds: 8);

final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');

final class _SecurityAttributes extends Struct {
  @Uint32()
  external int nLength;

  external Pointer<Void> lpSecurityDescriptor;

  @Int32()
  external int bInheritHandle;
}

final class _StartupInfoW extends Struct {
  @Uint32()
  external int cb;

  external Pointer<Void> lpReserved;

  external Pointer<Void> lpDesktop;

  external Pointer<Void> lpTitle;

  @Uint32()
  external int dwX;

  @Uint32()
  external int dwY;

  @Uint32()
  external int dwXSize;

  @Uint32()
  external int dwYSize;

  @Uint32()
  external int dwXCountChars;

  @Uint32()
  external int dwYCountChars;

  @Uint32()
  external int dwFillAttribute;

  @Uint32()
  external int dwFlags;

  @Uint16()
  external int wShowWindow;

  @Uint16()
  external int cbReserved2;

  external Pointer<Void> lpReserved2;

  external Pointer<Void> hStdInput;

  external Pointer<Void> hStdOutput;

  external Pointer<Void> hStdError;
}

final class _ProcessInformation extends Struct {
  external Pointer<Void> hProcess;

  external Pointer<Void> hThread;

  @Uint32()
  external int dwProcessId;

  @Uint32()
  external int dwThreadId;
}

// ---------------------------------------------------------------------------
// Win32 函数绑定
// ---------------------------------------------------------------------------

typedef _CreateProcessWNative = Int32 Function(
  Pointer<Utf16> lpApplicationName,
  Pointer<Utf16> lpCommandLine,
  Pointer<_SecurityAttributes> lpProcessAttributes,
  Pointer<_SecurityAttributes> lpThreadAttributes,
  Int32 bInheritHandles,
  Uint32 dwCreationFlags,
  Pointer<Void> lpEnvironment,
  Pointer<Utf16> lpCurrentDirectory,
  Pointer<_StartupInfoW> lpStartupInfo,
  Pointer<_ProcessInformation> lpProcessInformation,
);

typedef _CreateProcessWDart = int Function(
  Pointer<Utf16> lpApplicationName,
  Pointer<Utf16> lpCommandLine,
  Pointer<_SecurityAttributes> lpProcessAttributes,
  Pointer<_SecurityAttributes> lpThreadAttributes,
  int bInheritHandles,
  int dwCreationFlags,
  Pointer<Void> lpEnvironment,
  Pointer<Utf16> lpCurrentDirectory,
  Pointer<_StartupInfoW> lpStartupInfo,
  Pointer<_ProcessInformation> lpProcessInformation,
);

typedef _CreatePipeNative = Int32 Function(
  Pointer<Pointer<Void>> hReadPipe,
  Pointer<Pointer<Void>> hWritePipe,
  Pointer<_SecurityAttributes> lpPipeAttributes,
  Uint32 nSize,
);

typedef _CreatePipeDart = int Function(
  Pointer<Pointer<Void>> hReadPipe,
  Pointer<Pointer<Void>> hWritePipe,
  Pointer<_SecurityAttributes> lpPipeAttributes,
  int nSize,
);

typedef _SetHandleInformationNative = Int32 Function(
  Pointer<Void> hObject,
  Uint32 dwMask,
  Uint32 dwFlags,
);

typedef _SetHandleInformationDart = int Function(
  Pointer<Void> hObject,
  int dwMask,
  int dwFlags,
);

typedef _CloseHandleNative = Int32 Function(Pointer<Void> hObject);

typedef _CloseHandleDart = int Function(Pointer<Void> hObject);

typedef _WaitForSingleObjectNative = Uint32 Function(
  Pointer<Void> hHandle,
  Uint32 dwMilliseconds,
);

typedef _WaitForSingleObjectDart = int Function(
  Pointer<Void> hHandle,
  int dwMilliseconds,
);

typedef _GetExitCodeProcessNative = Int32 Function(
  Pointer<Void> hProcess,
  Pointer<Uint32> lpExitCode,
);

typedef _GetExitCodeProcessDart = int Function(
  Pointer<Void> hProcess,
  Pointer<Uint32> lpExitCode,
);

typedef _PeekNamedPipeNative = Int32 Function(
  Pointer<Void> hNamedPipe,
  Pointer<Void> lpBuffer,
  Uint32 nBufferSize,
  Pointer<Uint32> lpBytesAvail,
  Pointer<Uint32> lpBytesLeftThisMessage,
  Pointer<Uint32> lpTotalBytesLeft,
);

typedef _PeekNamedPipeDart = int Function(
  Pointer<Void> hNamedPipe,
  Pointer<Void> lpBuffer,
  int nBufferSize,
  Pointer<Uint32> lpBytesAvail,
  Pointer<Uint32> lpBytesLeftThisMessage,
  Pointer<Uint32> lpTotalBytesLeft,
);

typedef _ReadFileNative = Int32 Function(
  Pointer<Void> hFile,
  Pointer<Uint8> lpBuffer,
  Uint32 nNumberOfBytesToRead,
  Pointer<Uint32> lpNumberOfBytesRead,
  Pointer<Void> lpOverlapped,
);

typedef _ReadFileDart = int Function(
  Pointer<Void> hFile,
  Pointer<Uint8> lpBuffer,
  int nNumberOfBytesToRead,
  Pointer<Uint32> lpNumberOfBytesRead,
  Pointer<Void> lpOverlapped,
);

typedef _GetLastErrorNative = Uint32 Function();

typedef _GetLastErrorDart = int Function();

final _CreateProcessWDart _createProcessW =
    _kernel32.lookupFunction<_CreateProcessWNative, _CreateProcessWDart>(
      'CreateProcessW',
    );

final _CreatePipeDart _createPipe =
    _kernel32.lookupFunction<_CreatePipeNative, _CreatePipeDart>('CreatePipe');

final _SetHandleInformationDart _setHandleInformation = _kernel32
    .lookupFunction<_SetHandleInformationNative, _SetHandleInformationDart>(
      'SetHandleInformation',
    );

final _CloseHandleDart _closeHandle = _kernel32
    .lookupFunction<_CloseHandleNative, _CloseHandleDart>('CloseHandle');

final _WaitForSingleObjectDart _waitForSingleObject = _kernel32
    .lookupFunction<_WaitForSingleObjectNative, _WaitForSingleObjectDart>(
      'WaitForSingleObject',
    );

final _GetExitCodeProcessDart _getExitCodeProcess = _kernel32
    .lookupFunction<_GetExitCodeProcessNative, _GetExitCodeProcessDart>(
      'GetExitCodeProcess',
    );

final _PeekNamedPipeDart _peekNamedPipe = _kernel32
    .lookupFunction<_PeekNamedPipeNative, _PeekNamedPipeDart>('PeekNamedPipe');

final _ReadFileDart _readFile = _kernel32
    .lookupFunction<_ReadFileNative, _ReadFileDart>('ReadFile');

final _GetLastErrorDart _getLastError = _kernel32
    .lookupFunction<_GetLastErrorNative, _GetLastErrorDart>('GetLastError');

// ---------------------------------------------------------------------------
// 实现
// ---------------------------------------------------------------------------

Future<ProcessResult> _runWindows(
  String executable,
  List<String> arguments,
) async {
  // `reg` / `sc` / `w32tm` 这类只给名字的命令，先按系统搜索顺序解析成绝对路径，
  // 避免 CreateProcess 受当前工作目录影响找不到。
  final exePath = _resolveExecutable(executable);

  final sa = calloc<_SecurityAttributes>();
  final outRead = calloc<Pointer<Void>>();
  final outWrite = calloc<Pointer<Void>>();
  final errRead = calloc<Pointer<Void>>();
  final errWrite = calloc<Pointer<Void>>();
  final si = calloc<_StartupInfoW>();
  final pi = calloc<_ProcessInformation>();
  final avail = calloc<Uint32>();
  final readCount = calloc<Uint32>();
  final buf = calloc<Uint8>(_readChunk);
  final appName = exePath.toNativeUtf16();
  final cmdLine = ([exePath, ...arguments].map(_quote).join(' ')).toNativeUtf16();

  var outOpen = false;
  var errOpen = false;
  var processOpen = false;

  try {
    sa.ref
      ..nLength = sizeOf<_SecurityAttributes>()
      ..lpSecurityDescriptor = nullptr
      ..bInheritHandle = 1;

    if (_createPipe(outRead, outWrite, sa, 0) == 0) {
      throw ProcessException(
        executable,
        arguments,
        '创建 stdout 管道失败（错误码 ${_getLastError()}）',
      );
    }
    outOpen = true;
    if (_createPipe(errRead, errWrite, sa, 0) == 0) {
      throw ProcessException(
        executable,
        arguments,
        '创建 stderr 管道失败（错误码 ${_getLastError()}）',
      );
    }
    errOpen = true;

    // 读端只给父进程用，不传给子进程。
    _setHandleInformation(outRead.value, _handleFlagInherit, 0);
    _setHandleInformation(errRead.value, _handleFlagInherit, 0);

    si.ref
      ..cb = sizeOf<_StartupInfoW>()
      ..dwFlags = _startfUseStdHandles
      ..hStdInput = nullptr
      ..hStdOutput = outWrite.value
      ..hStdError = errWrite.value;

    final started = _createProcessW(
      appName,
      cmdLine,
      nullptr,
      nullptr,
      1,
      _createNoWindow,
      nullptr,
      nullptr,
      si,
      pi,
    );
    if (started == 0) {
      throw ProcessException(
        executable,
        arguments,
        'CreateProcess 失败（错误码 ${_getLastError()}）',
      );
    }
    processOpen = true;

    // 写端已交给子进程，父进程关掉自己这份。
    _closeHandle(outWrite.value);
    outWrite.value = nullptr;
    _closeHandle(errWrite.value);
    errWrite.value = nullptr;

    final outBytes = BytesBuilder(copy: false);
    final errBytes = BytesBuilder(copy: false);
    while (true) {
      _pump(outRead.value, outBytes, avail, readCount, buf);
      _pump(errRead.value, errBytes, avail, readCount, buf);
      if (_waitForSingleObject(pi.ref.hProcess, 0) == _waitObject0) break;
      await Future<void>.delayed(_pollInterval);
    }
    // 进程退出后管道里可能还剩数据，再收一次。
    _drainAfterExit(outRead.value, outBytes, readCount, buf);
    _drainAfterExit(errRead.value, errBytes, readCount, buf);

    final code = calloc<Uint32>();
    try {
      _getExitCodeProcess(pi.ref.hProcess, code);
      return ProcessResult(
        pi.ref.dwProcessId,
        code.value,
        _decode(outBytes.takeBytes()),
        _decode(errBytes.takeBytes()),
      );
    } finally {
      calloc.free(code);
    }
  } finally {
    if (processOpen) {
      _closeHandle(pi.ref.hThread);
      _closeHandle(pi.ref.hProcess);
    }
    if (outWrite.value.address != 0) _closeHandle(outWrite.value);
    if (errWrite.value.address != 0) _closeHandle(errWrite.value);
    if (outOpen) _closeHandle(outRead.value);
    if (errOpen) _closeHandle(errRead.value);

    malloc.free(appName);
    malloc.free(cmdLine);
    calloc.free(sa);
    calloc.free(outRead);
    calloc.free(outWrite);
    calloc.free(errRead);
    calloc.free(errWrite);
    calloc.free(si);
    calloc.free(pi);
    calloc.free(avail);
    calloc.free(readCount);
    calloc.free(buf);
  }
}

/// 进程退出后把管道读到空。
void _drainAfterExit(
  Pointer<Void> pipe,
  BytesBuilder sink,
  Pointer<Uint32> readCount,
  Pointer<Uint8> buf,
) {
  while (true) {
    readCount.value = 0;
    if (_readFile(pipe, buf, _readChunk, readCount, nullptr) == 0) return;
    final got = readCount.value;
    if (got == 0) return;
    sink.add(Uint8List.fromList(buf.asTypedList(got)));
  }
}

/// 把管道里当前可读的数据全部搬进 [sink]。
void _pump(
  Pointer<Void> pipe,
  BytesBuilder sink,
  Pointer<Uint32> avail,
  Pointer<Uint32> readCount,
  Pointer<Uint8> buf,
) {
  while (true) {
    avail.value = 0;
    // 注意 nBufferSize 必须大于 0：传 0 时 PeekNamedPipe 虽然返回成功，
    // 但可用字节数恒为 0，会误判成「子进程没有输出」。
    if (_peekNamedPipe(pipe, buf.cast<Void>(), _readChunk, avail, nullptr, nullptr) ==
        0) {
      return;
    }
    final available = avail.value;
    if (available == 0) return;
    final want = available > _readChunk ? _readChunk : available;
    readCount.value = 0;
    if (_readFile(pipe, buf, want, readCount, nullptr) == 0) return;
    final got = readCount.value;
    if (got == 0) return;
    sink.add(Uint8List.fromList(buf.asTypedList(got)));
  }
}

/// 按 Windows 命令行规则给单个参数加引号（反斜杠要成对转义）。
String _quote(String arg) {
  if (arg.isEmpty) return '""';
  if (!arg.contains(RegExp(r'[ \t\n\v"]'))) return arg;
  final out = StringBuffer('"');
  var backslashes = 0;
  for (final ch in arg.split('')) {
    if (ch == '\\') {
      backslashes++;
      continue;
    }
    if (ch == '"') {
      out.write('\\' * (backslashes * 2 + 1));
      out.write('"');
      backslashes = 0;
      continue;
    }
    if (backslashes > 0) {
      out.write('\\' * backslashes);
      backslashes = 0;
    }
    out.write(ch);
  }
  if (backslashes > 0) out.write('\\' * (backslashes * 2));
  out.write('"');
  return out.toString();
}

/// 只给了文件名（如 `reg`）时，按 System32 / Windows / PATH 顺序找出真实路径。
String _resolveExecutable(String name) {
  if (name.contains('\\') || name.contains('/')) return name;
  final hasExtension = RegExp(r'\.\w+$').hasMatch(name);
  final systemRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
  final dirs = <String>[
    '$systemRoot\\System32',
    systemRoot,
    ...(Platform.environment['PATH'] ?? '')
        .split(';')
        .map((d) => d.replaceAll('"', '').trim())
        .where((d) => d.isNotEmpty),
  ];
  for (final dir in dirs) {
    final candidates = hasExtension
        ? <String>['$dir\\$name']
        : <String>['$dir\\$name.exe', '$dir\\$name'];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) return candidate;
    }
  }
  return name;
}

String _decode(List<int> bytes) {
  if (bytes.isEmpty) return '';
  try {
    return systemEncoding.decode(bytes);
  } catch (_) {
    return utf8.decode(bytes, allowMalformed: true);
  }
}
