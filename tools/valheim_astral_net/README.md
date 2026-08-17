# Valheim Astral 局域网

在听服 `ZSteamSocket.StartHost` 之外再开 Steam Networking **IP listen（UDP 2456）**，用自管 UDP **2460** 广播发现房间，并在加入列表加 **Astral局域网** 页。走原版 `SetServerHost(ip, port, Steamworks)`，不要用 `Connect(host, port)`。

开房请保持 **跨平台关闭**（插件会强制关掉），否则会走 PlayFab，听服不绑 IP。

## 编译

本机需要 Valheim `valheim_Data/Managed`（默认 `E:\Valheim\valheim_Data\Managed`）。

```bat
cd tools\valheim_astral_net
dotnet build -c Release AstralValheimNet.sln
```

预编译副本在 `dist/AstralValheimNet.dll`（CI 无游戏程序集，不现场编）。改完请确认 dist 已更新。

安装布局：共用 `native/inject/astral_mono_inject.exe`，本插件 `native/valheim/AstralValheimNet.dll`。

## 用法

1. Astral 创建或加入 **Valheim** 房间（会开 UDP 广播转发）
2. 启动 `valheim.exe`，进房后 Astral 自动注入（约 8 秒）
3. 主菜单右上角出现 **Astral已注入 · F7**
4. **开房**：开始游戏面板会关掉跨平台，并提示走 Steam IP 2456
5. **加入**：服务器列表最左侧 **Astral局域网**，点选后加入；或 F7 填 `IP:2456`

两边必须是不同 Steam 账号。发现口 UDP `2460`，游戏口 UDP `2456`。
