# Astral Raft IP

把新版 Raft（PlayFab `SendP2P`）换成 TCP `IP:端口`，并由 Astral 进房后自动注入。编译时用最新 `Managed`（本机可放 `C:\Users\baika\Downloads\cs`）。

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
4. **新世界 / 载入世界**：勾选 **启用Astral局域网**（Steam 离线也能建房），联机权限不要选「不允许」
5. **加入世界**：新版 UI 会去掉「离线不可用」，标题 **加入astral房间**，列表 **lan发现**，点刷新即可。第一次加入会等场景加载完再向房主要世界，不再被 ConnectingBox 超时踢回主页。

两边必须是不同 Steam 账号。TCP `6488`，发现 UDP `6489` 广播。

## 手动注入（备用）

```bat
tools\raft_astral_net\bin\injector_rs\astral_mono_inject.exe --watch Raft --dll tools\raft_astral_net\dist\AstralRaftNet.dll
```

注入日志（控制台即时输出，同时写文件）：exe 旁 / DLL 旁 / `%TEMP%\astral_mono_inject.log`。成功行含 `injected pid=`。

或旧版 C# 注入器（同样自动等进程/Mono，并写日志）：

```bat
tools\raft_astral_net\bin\injector\AstralRaftInject.exe --watch Raft --dll tools\raft_astral_net\dist\AstralRaftNet.dll
```

日志：exe 旁 / DLL 旁 / `%TEMP%\AstralRaftInject.log`。成功行含 `injected pid=`。

F7 仍可开备用 IP 面板。
