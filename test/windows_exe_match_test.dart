import 'package:astral_game/data/services/windows_game_process.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('matches basename and stem', () {
    expect(windowsExeMatches(r'C:\Games\Raft.exe', 'raft.exe'), isTrue);
    expect(windowsExeMatches('Raft.exe', 'raft'), isTrue);
    expect(windowsExeMatches('chrome.exe', 'raft.exe'), isFalse);
  });

  test('matchesAny checks exe and path', () {
    const proc = WindowsGameProcess(
      pid: 1,
      exe: 'Raft.exe',
      title: '',
      path: r'D:\Steam\steamapps\common\Raft\Raft.exe',
      udpPorts: [],
    );
    expect(windowsExeMatchesAny(proc, ['raft.exe']), isTrue);
    expect(windowsExeMatchesAny(proc, ['unrelated.exe']), isFalse);
  });
}
