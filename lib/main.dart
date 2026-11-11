import 'dart:async';
import 'dart:io';

import 'package:astral_game/data/services/app_settings_service.dart';
import 'package:astral_game/data/services/home_widget_sync_service.dart';
import 'package:astral_game/data/services/join_link_service.dart';
import 'package:astral_game/data/services/shortcut_service.dart';
import 'package:astral_game/data/services/steam_selftest_service.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/utils/join_protocol.dart';
import 'package:astral_game/utils/runtime_platform.dart';
import 'package:astral_game/utils/single_instance_guard.dart';
import 'package:home_widget/home_widget.dart';
import 'package:astral_game/data/services/node_management_service.dart';
import 'package:astral_game/data/state/settings_state.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'ui/app.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // 由开机启动项写入的标记，只有这种方式拉起时才考虑「启动后到托盘」。
  final launchedAtBoot = args.contains('--autostart');

  // 零点击自检：--selftest-host / --selftest-guest，跑完写报告并退出。
  // 不 runApp，窗口保持隐藏，不抢前台、不需要鼠标操作。
  final selfTest = _parseSelfTestRequest(args);

  if (!await SingleInstanceGuard.tryAcquire()) {
    exit(0);
  }

  if (RuntimePlatform.isAndroid) {
    HomeWidget.registerInteractivityCallback(homeWidgetBackgroundCallback);
  }

  // Initialize window_manager only on desktop platforms
  if (RuntimePlatform.isDesktop) {
    await windowManager.ensureInitialized();

    const WindowOptions windowOptions = WindowOptions(
      size: Size(940, 560),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
    );

    // 必须 await：尺寸/居中是异步应用的，不 await 的话原生窗口会先按默认
    // 位置(10,10)显示出来，再跳到屏幕中央。
    await windowManager.waitUntilReadyToShow(windowOptions);
  }

  // 初始化完成后再 runApp：窗口在首帧渲染后才显示，不会出现空窗口或加载页。
  // 启动耗时已在 setupDI 内做了并发化，尽量压短这段等待。
  // runApp 之前的任何一步抛异常，用户都只能看到 LaunchTheme 的黑屏，
  // 因此统一兜底成可见的错误页，便于定位（含缺少 Rust 动态库等情况）。
  try {
    await setupDI();

    // 自检命令行模式：不启动 UI，直接跑完写报告后退出。
    if (selfTest != null) {
      exit(await _runSelfTest(selfTest));
    }

    await registerJoinProtocol();

    // 冷启动兜底：Linux 的 app_links 插件在窗口创建时才注册，拿不到首个
    // command-line；Windows/macOS 的链接也可能以参数形式传入。先解析一遍。
    getIt<JoinLinkService>().considerLaunchArguments(args);

    // 自检脚本（--steam-selftest）：本次运行直接露出 Steam Tab 与自检入口。
    getIt<SettingsState>().applySelfTestLaunch(args);

    getIt<NodeManagementService>().initUserInfo();

    if (RuntimePlatform.isAndroid) {
      refreshAndroidHomeWidgets();
    }
  } catch (error, stackTrace) {
    debugPrint('启动初始化失败: $error\n$stackTrace');
    // 自检模式不弹 UI 错误页，直接落一份失败报告后退出。
    if (selfTest != null) {
      await _writeSelfTestFailure(
        selfTest,
        DateTime.now(),
        '启动初始化失败: $error',
      );
      exit(3);
    }
    runApp(_StartupErrorApp(error: error));
    // 原生侧不再自动显示窗口，兜底页也要主动显示一次。
    if (RuntimePlatform.isDesktop) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_showMainWindow());
      });
    }
    return;
  }

  // 是否开机静默驻留托盘，必须在 setupDI 之后判断：prefs 此时才加载完成。
  // 原生侧在 --autostart 时不再自动显示窗口，显示与否完全由这里决定。
  final startToTray =
      launchedAtBoot && getIt<AppSettingsService>().getStartToTray();

  runApp(const AstralGameApp());

  if (RuntimePlatform.isDesktop && !startToTray) {
    // 等首帧渲染完再显示，避免出现空白窗口。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_showMainWindow());
    });
  }
}

Future<void> _showMainWindow() async {
  await windowManager.show();
  await windowManager.focus();
}

/// 零点击自检的启动参数。
class _SelfTestRequest {
  const _SelfTestRequest({required this.host, this.lobbyId});

  /// true = 房主（建房等客人），false = 客人（搜房或直达大厅）。
  final bool host;

  /// 客人直连的大厅 id；空表示自动搜房。
  final String? lobbyId;
}

/// 解析 `--selftest-host` / `--selftest-guest [--lobby=<id>]`。
_SelfTestRequest? _parseSelfTestRequest(List<String> args) {
  final host = args.contains('--selftest-host');
  final guest = args.contains('--selftest-guest');
  if (!host && !guest) return null;

  String? lobbyId;
  for (final arg in args) {
    if (arg.startsWith('--lobby=')) {
      lobbyId = arg.substring('--lobby='.length).trim();
    } else if (arg.startsWith('--selftest-lobby=')) {
      // 兼容上一版脚本参数。
      lobbyId = arg.substring('--selftest-lobby='.length).trim();
    }
  }
  return _SelfTestRequest(
    host: host,
    lobbyId: (lobbyId == null || lobbyId.isEmpty) ? null : lobbyId,
  );
}

/// 跑一次命令行自检并返回退出码：0 成功、2 未通过、3 启动/执行异常。
Future<int> _runSelfTest(_SelfTestRequest request) async {
  final startedAt = DateTime.now();
  try {
    final result = await SteamSelfTestService().run(
      host: request.host,
      targetLobbyId: request.lobbyId,
      onProgress: (message) => debugPrint('[selftest] $message'),
    );
    debugPrint('[selftest] 报告已写入 ${result.path}');
    return result.success ? 0 : 2;
  } catch (error, stackTrace) {
    debugPrint('[selftest] 失败: $error\n$stackTrace');
    await _writeSelfTestFailure(request, startedAt, '$error');
    return 3;
  }
}

/// 自检在写报告前就失败（组网房未退出、未开调试日志、找不到桌面等）时，
/// 仍然在桌面留一份最小报告，避免用户只看到进程一闪而过。
Future<void> _writeSelfTestFailure(
  _SelfTestRequest request,
  DateTime startedAt,
  String reason,
) async {
  final role = request.host ? 'host' : 'guest';
  final report = StringBuffer()
    ..writeln('===== 结论 =====')
    ..writeln('结果: 失败（启动自检失败）')
    ..writeln(
      '角色: ${request.host ? '房主' : '客人'} | 大厅 id: '
      '${request.lobbyId ?? '—'}',
    )
    ..writeln('进房: 否 | 成员: 0 人 | 传输: 未就绪')
    ..writeln('覆盖层: 未知 | 邀请面板: 未调用')
    ..writeln('原因: $reason')
    ..writeln('===== 明细 =====')
    ..writeln('开始: ${_fmtTime(startedAt)}')
    ..writeln('结束: ${_fmtTime(DateTime.now())}');
  final dir = _selfTestReportDir();
  final name =
      'astral-steam-selftest-$role-${_stampTime(startedAt)}.log';
  final file = File('$dir\\$name');
  try {
    await file.writeAsString(report.toString(), flush: true);
    debugPrint('[selftest] 失败报告已写入 ${file.path}');
  } catch (error) {
    debugPrint('[selftest] 失败报告写入失败: $error');
  }
}

/// 桌面目录；DI 不可用或桌面被重定向时退到临时目录。
String _selfTestReportDir() {
  try {
    final desktop = getIt<ShortcutService>().desktopDirectory();
    if (desktop != null && desktop.isNotEmpty) return desktop;
  } catch (_) {
    // setupDI 尚未完成时 ShortcutService 可能未注册，走下面的兜底。
  }
  final home = Platform.environment['USERPROFILE'];
  final desktop = home == null ? null : '$home\\Desktop';
  if (desktop != null && Directory(desktop).existsSync()) return desktop;
  return Directory.systemTemp.path;
}

String _fmtTime(DateTime t) =>
    '${t.year}-${_two(t.month)}-${_two(t.day)} '
    '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

String _stampTime(DateTime t) =>
    '${t.year}${_two(t.month)}${_two(t.day)}-'
    '${_two(t.hour)}${_two(t.minute)}${_two(t.second)}';

String _two(int value) => value.toString().padLeft(2, '0');

/// 启动初始化失败时的兜底页：只依赖 Flutter 自身，不依赖任何服务。
class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF101014),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.white70,
                    size: 40,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '应用初始化失败',
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
