import 'package:astral_game/src/rust/api/pear.dart' as rust_pear;

/// Holepunch Pear(HyperDHT) 组网传输的 Dart 门面。
///
/// Rust 侧负责 Node 侧车、wintun 虚拟网卡、星型组网转发与应用内 RPC；
/// 这里只做参数组装。
class PearTransportService {
  /// 读取 Pear 状态（首次调用会拉起后台线程并检测 Node 运行时）。
  Future<rust_pear.PearStatusInfo> status() => rust_pear.pearStatus();

  /// 读取当前房间成员 / 虚拟 IP。
  Future<rust_pear.PearRoomInfo> roomInfo() => rust_pear.pearRoomInfo();

  Future<int> myPeerId() => rust_pear.pearMyPeerId();

  /// 房主：在 HyperDHT 上发布房间并等待成员加入，返回含本机公钥的状态。
  Future<rust_pear.PearStatusInfo> startHost({
    required String joinToken,
    required String nickname,
  }) {
    return rust_pear.pearStart(
      host: true,
      hostKey: '',
      joinToken: joinToken,
      nickname: nickname,
    );
  }

  /// 客机：按房主 HyperDHT 公钥连入同一虚拟局域网。
  Future<rust_pear.PearStatusInfo> startGuest({
    required String hostKey,
    required String joinToken,
    required String nickname,
  }) {
    return rust_pear.pearStart(
      host: false,
      hostKey: hostKey,
      joinToken: joinToken,
      nickname: nickname,
    );
  }

  Future<void> stop() => rust_pear.pearStop();
}
