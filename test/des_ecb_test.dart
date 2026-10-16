import 'dart:typed_data';

import 'package:astral_game/utils/des_ecb.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _hex(String value) {
  final out = Uint8List(value.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(value.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String _toHex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

void main() {
  test('DES/ECB 解密结果与标准测试向量一致', () {
    final key = _hex('133457799BBCDFF1');
    final cipher = _hex('85E813540F0AB405');
    expect(_toHex(DesEcb.decrypt(cipher, key)), '0123456789ABCDEF');
  });

  test('DES/ECB 支持多块密文', () {
    final key = _hex('133457799BBCDFF1');
    final cipher = _hex('85E813540F0AB40585E813540F0AB405');
    expect(
      _toHex(DesEcb.decrypt(cipher, key)),
      '0123456789ABCDEF0123456789ABCDEF',
    );
  });

  test('密钥长度必须为 8 字节', () {
    expect(
      () => DesEcb.decrypt(_hex('85E813540F0AB405'), _hex('1334')),
      throwsArgumentError,
    );
  });

  test('PKCS5 去填充', () {
    expect(_toHex(DesEcb.unpadPkcs5(_hex('AABBCCDD030303'))), 'AABBCCDD');
    expect(
      _toHex(DesEcb.unpadPkcs5(_hex('AABBCCDD0808080808080808'))),
      'AABBCCDD',
    );
    expect(
      _toHex(DesEcb.unpadPkcs5(_hex('AABBCCDD00000000'))),
      'AABBCCDD00000000',
    );
    expect(DesEcb.unpadPkcs5(Uint8List(0)), isEmpty);
  });
}
