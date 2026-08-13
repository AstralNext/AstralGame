/// 房间组网流量快照（本机视角：对端合计）。
class RoomTrafficStats {
  const RoomTrafficStats({
    required this.rxTotalBytes,
    required this.txTotalBytes,
    required this.rxRateBps,
    required this.txRateBps,
  });

  static const zero = RoomTrafficStats(
    rxTotalBytes: 0,
    txTotalBytes: 0,
    rxRateBps: 0,
    txRateBps: 0,
  );

  /// 累计下载（字节）。
  final int rxTotalBytes;

  /// 累计上传（字节）。
  final int txTotalBytes;

  /// 实时下载速率（字节/秒）。
  final double rxRateBps;

  /// 实时上传速率（字节/秒）。
  final double txRateBps;

  bool get isZero =>
      rxTotalBytes == 0 &&
      txTotalBytes == 0 &&
      rxRateBps <= 0 &&
      txRateBps <= 0;
}
