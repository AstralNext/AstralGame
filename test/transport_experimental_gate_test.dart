import 'package:astral_game/data/models/transport_mode.dart';
import 'package:astral_game/data/services/app_settings_service.dart';
import 'package:astral_game/data/state/settings_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Steam 组网「实验性功能 + 仅 Windows」的判定入口与启动回落。
///
/// 本机是 Windows，非 Windows 分支通过注入 [TransportPlatform] 覆盖。
void main() {
  group('TransportGate：模式 + 平台 + 开关', () {
    test('EasyTier 在所有平台、开关任意状态都可用', () {
      for (final platform in TransportPlatform.values) {
        for (final enabled in [false, true]) {
          final gate = TransportGate(
            platform: platform,
            experimentalSteamEnabled: enabled,
          );
          expect(gate.isAvailable(TransportMode.easytier), isTrue);
        }
      }
    });

    test('Steam 只在 Windows 且开关打开时可用', () {
      const enabled = TransportGate(
        platform: TransportPlatform.windows,
        experimentalSteamEnabled: true,
      );
      const disabled = TransportGate(
        platform: TransportPlatform.windows,
        experimentalSteamEnabled: false,
      );
      const mac = TransportGate(
        platform: TransportPlatform.macOS,
        experimentalSteamEnabled: true,
      );
      expect(enabled.isAvailable(TransportMode.steam), isTrue);
      expect(disabled.isAvailable(TransportMode.steam), isFalse);
      expect(mac.isAvailable(TransportMode.steam), isFalse);
    });

    test('可用模式列表随平台与开关收缩', () {
      const enabled = TransportGate(
        platform: TransportPlatform.windows,
        experimentalSteamEnabled: true,
      );
      const disabled = TransportGate(
        platform: TransportPlatform.windows,
        experimentalSteamEnabled: false,
      );
      const linux = TransportGate(
        platform: TransportPlatform.linux,
        experimentalSteamEnabled: true,
      );
      expect(enabled.availableModes, TransportMode.values);
      expect(disabled.availableModes, [TransportMode.easytier]);
      expect(linux.availableModes, [TransportMode.easytier]);
    });

    test('不可用模式回落 EasyTier', () {
      const enabled = TransportGate(
        platform: TransportPlatform.windows,
        experimentalSteamEnabled: true,
      );
      const disabled = TransportGate(
        platform: TransportPlatform.windows,
        experimentalSteamEnabled: false,
      );
      const android = TransportGate(
        platform: TransportPlatform.android,
        experimentalSteamEnabled: true,
      );
      expect(enabled.fallback(TransportMode.steam), TransportMode.steam);
      expect(disabled.fallback(TransportMode.steam), TransportMode.easytier);
      expect(android.fallback(TransportMode.steam), TransportMode.easytier);
      expect(enabled.fallback(TransportMode.easytier), TransportMode.easytier);
    });

    test('不可用原因区分平台与开关', () {
      const disabled = TransportGate(
        platform: TransportPlatform.windows,
        experimentalSteamEnabled: false,
      );
      const mac = TransportGate(
        platform: TransportPlatform.macOS,
        experimentalSteamEnabled: true,
      );
      expect(disabled.unavailableReason(TransportMode.easytier), isNull);
      expect(
        disabled.unavailableReason(TransportMode.steam),
        allOf(contains('实验性功能'), contains('设置')),
      );
      // 非 Windows 不允许出现任何 Steam 相关提示。
      expect(mac.unavailableReason(TransportMode.steam), isNot(contains('Steam')));
      expect(mac.unavailableReason(TransportMode.steam), isNotEmpty);
    });

    test('只有 Windows 提供实验性开关入口', () {
      for (final platform in TransportPlatform.values) {
        final gate = TransportGate(
          platform: platform,
          experimentalSteamEnabled: true,
        );
        expect(
          gate.canToggleExperimentalSteam,
          platform == TransportPlatform.windows,
        );
      }
    });
  });

  group('SettingsState：持久化与启动回落', () {
    late AppSettingsService settings;

    Future<SettingsState> createState([Map<String, Object> initial = const {}]) async {
      SharedPreferences.setMockInitialValues(initial);
      settings = AppSettingsService(await SharedPreferences.getInstance());
      final state = SettingsState(settings);
      state.loadFromPersistence();
      return state;
    }

    test('实验性开关默认关闭，并能持久化', () async {
      final state = await createState();
      expect(state.experimentalSteam.value, isFalse);
      expect(state.transportMode.value, TransportMode.easytier);

      state.experimentalSteam.value = true;
      await state.saveToPersistence();
      expect(settings.getExperimentalSteamEnabled(), isTrue);

      final reloaded = SettingsState(settings)..loadFromPersistence();
      expect(reloaded.experimentalSteam.value, isTrue);
    });

    test('历史配置为 steam 但开关关闭：回落 easytier 并给出说明', () async {
      final state = await createState({'transport_mode': 'steam'});
      expect(state.transportMode.value, TransportMode.easytier);
      expect(state.transportFallbackNotice.value, isNotNull);
      expect(state.transportFallbackNotice.value, contains('EasyTier'));
      expect(state.transportGate.isAvailable(TransportMode.steam), isFalse);
    });

    test('开关打开时保留历史 steam 配置，且切回后立即失效', () async {
      final state = await createState({
        'transport_mode': 'steam',
        'experimental_steam_mode': true,
      });
      expect(state.transportMode.value, TransportMode.steam);
      expect(state.transportFallbackNotice.value, isNull);

      state.experimentalSteam.value = false;
      expect(state.transportGate.isAvailable(TransportMode.steam), isFalse);
      expect(state.transportGate.fallback(TransportMode.steam),
          TransportMode.easytier);
    });

    test('历史配置 pear 在开关关闭时同样回落 EasyTier', () async {
      final state = await createState({'transport_mode': 'pear'});
      expect(state.transportMode.value, TransportMode.easytier);
      expect(state.transportFallbackNotice.value, isNotNull);
    });
  });
}
