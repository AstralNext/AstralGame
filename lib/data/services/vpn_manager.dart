import 'package:astral_game/data/state/vpn_state.dart';
import 'package:astral_game/utils/client_runtime_info.dart';
import 'package:astral_game/utils/input_validator.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:astral_rust_core/p2p_service.dart';
import 'package:vpn_service_plugin/vpn_service_plugin.dart';

/// AstralGame 侧 VPN：委托 [AndroidVpnSession]，状态写入 [VpnState]。
class VpnManager {
  VpnManager(this.vpnState, P2PService p2p)
      : _session = AndroidVpnSession(
          applyTunFd: p2p.setTunFd,
          log: (level, message) {
            final msg = '[VpnManager] $message';
            if (level == 'error') {
              appLogger.e(msg);
            } else if (level == 'warn') {
              appLogger.w(msg);
            } else {
              appLogger.i(msg);
            }
          },
        ) {
    _session.onRevokedBySystem = (_) async {
      vpnState.setRunning(false);
      vpnState.setConnecting(false);
    };
  }

  final VpnState vpnState;
  final AndroidVpnSession _session;

  Future<bool> ensurePermission() => _session.ensurePermission();

  Future<bool> start({
    required String instanceId,
    required String ipv4Addr,
    int? mtu,
  }) async {
    vpnState.setConnecting(true);
    final finalIpv4 = AndroidVpnSession.withDefaultPrefix(ipv4Addr);
    final finalMtu = mtu ?? vpnState.mtu.value;
    vpnState.setIpv4Addr(finalIpv4);
    vpnState.setMtu(finalMtu);

    final routes = vpnState.customRoutes.value
        .map((r) => r.trim())
        .where((r) => InputValidator.validateCidr(r) == null)
        .toList(growable: false);

    final packageName = ClientRuntimeInfo.packageName;
    final disallowed =
        packageName.isEmpty ? const <String>[] : <String>[packageName];

    final ok = await _session.start(
      instanceId: instanceId,
      ipv4Addr: finalIpv4,
      mtu: finalMtu,
      routes: routes,
      disallowedApplications: disallowed,
    );
    vpnState.setConnecting(false);
    vpnState.setRunning(ok);
    return ok;
  }

  Future<void> stop() async {
    await _session.stop();
    vpnState.setRunning(false);
    vpnState.setConnecting(false);
  }

  void startListening() => _session.startListening();

  void dispose() {
    // Fire-and-forget; Game DI dispose 是同步路径。
    _session.dispose();
  }
}
