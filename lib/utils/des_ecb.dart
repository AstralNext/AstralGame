import 'dart:typed_data';

class DesEcb {
  DesEcb._();

  static Uint8List decrypt(Uint8List cipher, Uint8List key) {
    if (key.length != 8) {
      throw ArgumentError.value(key.length, 'key', 'DES 密钥必须是 8 字节');
    }
    final subkeys = _keySchedule(key);
    final out = BytesBuilder(copy: false);
    for (var i = 0; i + 8 <= cipher.length; i += 8) {
      out.add(_decryptBlock(Uint8List.sublistView(cipher, i, i + 8), subkeys));
    }
    return out.takeBytes();
  }

  static Uint8List decryptPkcs5(Uint8List cipher, Uint8List key) =>
      unpadPkcs5(decrypt(cipher, key));

  static Uint8List unpadPkcs5(Uint8List data) {
    if (data.isEmpty) return data;
    final pad = data.last;
    if (pad >= 1 && pad <= 8 && pad <= data.length) {
      return Uint8List.sublistView(data, 0, data.length - pad);
    }
    return data;
  }

  static Uint8List _decryptBlock(Uint8List block, List<Uint8List> subkeys) {
    final ip = _permute(_toBits(block), _ip);
    var left = Uint8List.sublistView(ip, 0, 32);
    var right = Uint8List.sublistView(ip, 32, 64);
    for (var i = subkeys.length - 1; i >= 0; i--) {
      final f = _feistel(right, subkeys[i]);
      final next = Uint8List(32);
      for (var j = 0; j < 32; j++) {
        next[j] = left[j] ^ f[j];
      }
      left = right;
      right = next;
    }
    final fp = _permute(_concat(right, left), _fp);
    final out = Uint8List(8);
    for (var i = 0; i < 64; i++) {
      if (fp[i] == 1) out[i >> 3] |= 1 << (7 - (i & 7));
    }
    return out;
  }

  static Uint8List _feistel(Uint8List r32, Uint8List subkey) {
    final expanded = _permute(r32, _e);
    final x = Uint8List(48);
    for (var i = 0; i < 48; i++) {
      x[i] = expanded[i] ^ subkey[i];
    }
    final sOut = Uint8List(32);
    for (var box = 0; box < 8; box++) {
      final base = box * 6;
      final row = (x[base] << 1) | x[base + 5];
      final col =
          (x[base + 1] << 3) |
          (x[base + 2] << 2) |
          (x[base + 3] << 1) |
          x[base + 4];
      final val = _s[box][row * 16 + col];
      sOut[box * 4] = (val >> 3) & 1;
      sOut[box * 4 + 1] = (val >> 2) & 1;
      sOut[box * 4 + 2] = (val >> 1) & 1;
      sOut[box * 4 + 3] = val & 1;
    }
    return _permute(sOut, _p);
  }

  static List<Uint8List> _keySchedule(Uint8List key) {
    final k = _permute(_toBits(key), _pc1);
    var c = Uint8List.sublistView(k, 0, 28);
    var d = Uint8List.sublistView(k, 28, 56);
    final subkeys = <Uint8List>[];
    for (final shift in _shifts) {
      c = _rotateLeft(c, shift);
      d = _rotateLeft(d, shift);
      subkeys.add(_permute(_concat(c, d), _pc2));
    }
    return subkeys;
  }

  static Uint8List _toBits(Uint8List bytes) {
    final bits = Uint8List(bytes.length * 8);
    for (var i = 0; i < bits.length; i++) {
      bits[i] = (bytes[i >> 3] >> (7 - (i & 7))) & 1;
    }
    return bits;
  }

  static Uint8List _permute(Uint8List bits, List<int> table) {
    final out = Uint8List(table.length);
    for (var i = 0; i < table.length; i++) {
      out[i] = bits[table[i] - 1];
    }
    return out;
  }

  static Uint8List _rotateLeft(Uint8List bits, int shift) {
    final n = bits.length;
    final out = Uint8List(n);
    for (var i = 0; i < n; i++) {
      out[i] = bits[(i + shift) % n];
    }
    return out;
  }

  static Uint8List _concat(Uint8List a, Uint8List b) {
    final out = Uint8List(a.length + b.length);
    out.setRange(0, a.length, a);
    out.setRange(a.length, out.length, b);
    return out;
  }

  static List<int> _table(String raw) => [
    for (final token in raw.split(RegExp(r'\s+')))
      if (token.isNotEmpty) int.parse(token),
  ];

  static final List<int> _ip = _table('''
58 50 42 34 26 18 10 2 60 52 44 36 28 20 12 4
62 54 46 38 30 22 14 6 64 56 48 40 32 24 16 8
57 49 41 33 25 17 9 1 59 51 43 35 27 19 11 3
61 53 45 37 29 21 13 5 63 55 47 39 31 23 15 7
''');

  static final List<int> _fp = _table('''
40 8 48 16 56 24 64 32 39 7 47 15 55 23 63 31
38 6 46 14 54 22 62 30 37 5 45 13 53 21 61 29
36 4 44 12 52 20 60 28 35 3 43 11 51 19 59 27
34 2 42 10 50 18 58 26 33 1 41 9 49 17 57 25
''');

  static final List<int> _e = _table('''
32 1 2 3 4 5 4 5 6 7 8 9 8 9 10 11 12 13 12 13
14 15 16 17 16 17 18 19 20 21 20 21 22 23 24 25
24 25 26 27 28 29 28 29 30 31 32 1
''');

  static final List<int> _p = _table('''
16 7 20 21 29 12 28 17 1 15 23 26 5 18 31 10
2 8 24 14 32 27 3 9 19 13 30 6 22 11 4 25
''');

  static final List<int> _pc1 = _table('''
57 49 41 33 25 17 9 1 58 50 42 34 26 18 10 2
59 51 43 35 27 19 11 3 60 52 44 36
63 55 47 39 31 23 15 7 62 54 46 38 30 22 14 6
61 53 45 37 29 21 13 5 28 20 12 4
''');

  static final List<int> _pc2 = _table('''
14 17 11 24 1 5 3 28 15 6 21 10 23 19 12 4 26 8 16 7 27 20 13 2
41 52 31 37 47 55 30 40 51 45 33 48 44 49 39 56 34 53 46 42 50 36 29 32
''');

  static const List<int> _shifts = [
    1,
    1,
    2,
    2,
    2,
    2,
    2,
    2,
    1,
    2,
    2,
    2,
    2,
    2,
    2,
    1,
  ];

  static final List<List<int>> _s = [
    _table('''
14 4 13 1 2 15 11 8 3 10 6 12 5 9 0 7
0 15 7 4 14 2 13 1 10 6 12 11 9 5 3 8
4 1 14 8 13 6 2 11 15 12 9 7 3 10 5 0
15 12 8 2 4 9 1 7 5 11 3 14 10 0 6 13
'''),
    _table('''
15 1 8 14 6 11 3 4 9 7 2 13 12 0 5 10
3 13 4 7 15 2 8 14 12 0 1 10 6 9 11 5
0 14 7 11 10 4 13 1 5 8 12 6 9 3 2 15
13 8 10 1 3 15 4 2 11 6 7 12 0 5 14 9
'''),
    _table('''
10 0 9 14 6 3 15 5 1 13 12 7 11 4 2 8
13 7 0 9 3 4 6 10 2 8 5 14 12 11 15 1
13 6 4 9 8 15 3 0 11 1 2 12 5 10 14 7
1 10 13 0 6 9 8 7 4 15 14 3 11 5 2 12
'''),
    _table('''
7 13 14 3 0 6 9 10 1 2 8 5 11 12 4 15
13 8 11 5 6 15 0 3 4 7 2 12 1 10 14 9
10 6 9 0 12 11 7 13 15 1 3 14 5 2 8 4
3 15 0 6 10 1 13 8 9 4 5 11 12 7 2 14
'''),
    _table('''
2 12 4 1 7 10 11 6 8 5 3 15 13 0 14 9
14 11 2 12 4 7 13 1 5 0 15 10 3 9 8 6
4 2 1 11 10 13 7 8 15 9 12 5 6 3 0 14
11 8 12 7 1 14 2 13 6 15 0 9 10 4 5 3
'''),
    _table('''
12 1 10 15 9 2 6 8 0 13 3 4 14 7 5 11
10 15 4 2 7 12 9 5 6 1 13 14 0 11 3 8
9 14 15 5 2 8 12 3 7 0 4 10 1 13 11 6
4 3 2 12 9 5 15 10 11 14 1 7 6 0 8 13
'''),
    _table('''
4 11 2 14 15 0 8 13 3 12 9 7 5 10 6 1
13 0 11 7 4 9 1 10 14 3 5 12 2 15 8 6
1 4 11 13 12 3 7 14 10 15 6 8 0 5 9 2
6 11 13 8 1 4 10 7 9 5 0 15 14 2 3 12
'''),
    _table('''
13 2 8 4 6 15 11 1 10 9 3 14 5 0 12 7
1 15 13 8 10 3 7 4 12 5 6 11 0 14 9 2
7 11 4 1 9 12 14 2 0 6 10 13 15 3 5 8
2 1 14 7 4 10 8 13 15 12 9 0 3 5 6 11
'''),
  ];
}
