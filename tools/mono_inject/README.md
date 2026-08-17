# 共用 Unity Mono 注入器

各游戏插件 DLL 仍分开放（Raft 在 `tools/raft_astral_net`，Valheim 在 `tools/valheim_astral_net`）。这里只编 `astral_mono_inject.exe`。

```bat
cargo build --release --manifest-path tools\mono_inject\Cargo.toml
```

安装后：`native/inject/astral_mono_inject.exe` + `native/<gameId>/<插件>.dll`。
