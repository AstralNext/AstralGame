import 'package:astral_game/data/models/speed_test_node.dart';
import 'package:astral_game/data/models/speed_test_result.dart';
import 'package:astral_game/data/services/connectivity_status_service.dart';
import 'package:astral_game/data/services/isp_info_service.dart';
import 'package:astral_game/data/services/screen_state_service.dart';
import 'package:astral_game/data/services/speed_test_service.dart';
import 'package:astral_game/data/state/speed_test_state.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/ui/pages/settings/speed_test_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SpeedTestState state;

  setUp(() {
    state = SpeedTestState(SpeedTestService());
    state.nodes.value = [
      const SpeedTestNode(
        ip: '124.74.52.254',
        port: '65499',
        name: '上海电信',
        province: '上海',
        city: '上海',
        operator: '电信',
      ),
      const SpeedTestNode(
        ip: '210.51.57.10',
        port: '65499',
        name: '上海联通',
        province: '上海',
        city: '上海',
        operator: '联通',
      ),
    ];
    state.selected.value = state.nodes.value.first;
    getIt.registerSingleton<SpeedTestState>(state);
    getIt.registerSingleton<IspInfoService>(
      IspInfoService(ConnectivityStatusService()),
    );
    getIt.registerSingleton<ScreenStateService>(ScreenStateService());
  });

  tearDown(() => getIt.reset());

  for (final size in const [Size(360, 640), Size(1280, 800)]) {
    final isNarrow = size.width < 600;
    testWidgets('测速页在 ${size.width.toInt()}x${size.height.toInt()} 正常', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      getIt<ScreenStateService>().updateScreenWidth(size.width);

      await tester.pumpWidget(const MaterialApp(home: SpeedTestPage()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('网络测速'), findsOneWidget);
      expect(find.text('开始测速后这里会绘制实时速率曲线'), findsOneWidget);
      expect(find.text('开始测速'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_downward_rounded), findsWidgets);
      expect(find.byIcon(Icons.arrow_upward_rounded), findsWidgets);
      expect(find.textContaining('省份 ·'), findsNothing);
      expect(find.textContaining('运营商 ·'), findsNothing);

      final button = tester.getTopLeft(find.text('开始测速'));
      final chart = tester.getTopLeft(find.text('开始测速后这里会绘制实时速率曲线'));
      if (isNarrow) {
        expect(button.dy, greaterThan(chart.dy));
      } else {
        expect(button.dx, lessThan(chart.dx));
      }

      await tester.tap(find.text('更换'));
      await tester.pumpAndSettle();
      expect(find.text('选择测速节点'), findsOneWidget);
      expect(find.text('共 2 个'), findsOneWidget);
      expect(find.text('搜索节点 / 地区'), findsOneWidget);
      expect(find.textContaining('124.74.52.254'), findsNothing);
      await tester.tap(find.text('上海联通'));
      await tester.pumpAndSettle();
      expect(state.selected.value?.ip, '210.51.57.10');

      state.samples.value = [
        for (var i = 0; i < 10; i++)
          SpeedTestSample(
            phase: SpeedTestPhase.download,
            elapsed: Duration(milliseconds: 300 + i * 200),
            mbps: 700 - i * 10,
          ),
        for (var i = 0; i < 10; i++)
          SpeedTestSample(
            phase: SpeedTestPhase.upload,
            elapsed: Duration(milliseconds: 2500 + i * 200),
            mbps: 140 + i * 2,
          ),
      ];
      state.liveDownloadLatencyMs.value = 42;
      state.liveUploadLatencyMs.value = 58;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('开始测速后这里会绘制实时速率曲线'), findsNothing);
      expect(find.text('610.0'), findsOneWidget);
      expect(find.text('158.0'), findsOneWidget);
      expect(find.text('延迟 42 ms'), findsOneWidget);
      expect(find.text('延迟 58 ms'), findsOneWidget);

      state.result.value = const SpeedTestResult(
        latencyMs: 32.4,
        downloadLatencyMs: 33,
        uploadLatencyMs: 61,
        downloadMbps: 828.1,
        uploadMbps: 148.4,
      );
      await tester.pumpAndSettle();
      expect(find.text('828.1'), findsOneWidget);
      expect(find.text('148.4'), findsOneWidget);
      expect(find.text('延迟 33 ms'), findsOneWidget);
      expect(find.text('延迟 61 ms'), findsOneWidget);

      state.result.value = const SpeedTestResult.failure('节点繁忙（排队超限）');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('节点繁忙（排队超限）'), findsOneWidget);

      state.running.value = true;
      await tester.pump();
      expect(find.text('测速中'), findsOneWidget);
      expect(find.text('开始测速'), findsNothing);
    });
  }
}
