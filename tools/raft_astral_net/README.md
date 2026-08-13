# Astral Raft IP

把 Raft 的 Steam P2P 换成 TCP `IP:端口`，并由 Astral 进房后自动注入。

## 编译

```bat
cd tools\raft_astral_net
dotnet build -c Release AstralRaftNet.sln
cargo build --release --manifest-path injector_rs\Cargo.toml
```

Windows 安装包 / `flutter build windows` 会把 `AstralRaftNet.dll` 与 `astral_mono_inject.exe` 拷到 `native/raft/`。

插件预编译副本在 `dist/AstralRaftNet.dll`（CI 无 Raft 游戏程序集，不现场编 Harmony）。本地改插件后请：

```bat
dotnet build -c Release AstralRaftNet.sln
copy bin\plugin\AstralRaftNet.dll dist\AstralRaftNet.dll
```

## 用法（推荐）

1. Astral 创建或加入 **Raft** 房间
2. 启动 `Raft.exe`，Astral 自动检测并注入
3. 游戏首页右上角出现 **Astral已注入**
4. **新世界 / 载入世界**：联机权限不要选「不允许」，勾选 **启用Astral局域网**
5. **加入世界**：标题为 **加入astral房间**，列表为 **lan发现**，点刷新即可

两边必须是不同 Steam 账号。TCP `6488`，发现 UDP `6489` 广播。

## 手动注入（备用）

```bat
tools\raft_astral_net\bin\injector_rs\astral_mono_inject.exe --watch Raft --dll tools\raft_astral_net\bin\plugin\AstralRaftNet.dll
```

或旧版 C# 注入器：

```bat
tools\raft_astral_net\bin\injector\AstralRaftInject.exe -p Raft
```

F7 仍可开备用 IP 面板。
