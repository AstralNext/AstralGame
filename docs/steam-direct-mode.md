# Steam 组网模式（实验）

设置 → 网络 → **Steam 直连（实验）**。开启后建房/进房不再创建 EasyTier 实例，
由 Rust 侧 `steam_tunnel` 用 Steam Datagram Relay（SDR）承载 IP 包，**自己创建虚拟网卡**，
组成一个真实的虚拟局域网。游戏按虚拟 IP 直连，不再做端口桥接或发现旁路。

只影响下一次建房/进房；连接中开关禁用。

## 目标与非目标

- 目标：Steam 模式与 EasyTier 模式**功能对等**——房间/邀请/短码/成员列表/虚拟 IP/延迟/
  应用内 RPC（开播游戏、资料、房主操作）都保留。
- 目标：局域网游戏无需改配置，按“同一局域网”方式搜索、进服。
- 非目标（第一版）：非 Windows 平台、IPv6 虚拟网、出口代理（不把 Steam 当公网网关）。

## 总架构

```
Flutter
  ConnectionService        建房/进房/邀请，按 transport 分支
  NodeManagementService    成员/虚拟 IP/延迟：数据源抽象（easytier | steam）
  PeerRpcClient/Router     同一套业务通道，传输后端可切换
        │ FRB
Rust  steam_tunnel（仅 Windows，替代 EasyTier 实例）
  ├ SteamRuntime    Client 单例、回调泵、连接状态、relay 状态、统计
  ├ TunAdapter      wintun.dll（L3），MTU 1280，metric 0
  ├ RoomController  房主/客人、成员表、虚拟 IP 分配、鉴权
  ├ ControlPlane    Hello / AssignIp / Roster / Ping / Bye（可靠消息）
  ├ DataPlane       TUN ↔ SDR 的 IP 包收发、广播/组播泛洪、按目标批量
  └ AppRpc          call / notify / reply / ping，经控制通道承载
```

拓扑（第一版）：**星型**。房主监听 P2P socket，客人连房主；所有数据经房主转发。
广播泛洪天然无环，房主是唯一权威成员表。

## 传输模型

- 单个 P2P 虚拟端口 `0xA57A`（`CreateListenSocketP2P` / `ConnectP2P`），
  控制与数据共用一条连接，按帧头区分。
- 帧头：

  ```
  u8  version   = 1
  u8  kind      = 0 IP包 | 1 控制 | 3 应用RPC
  u8  flags     = bit0 泛洪
  u8  reserved
  u32 src       = 发送方虚拟 IP（A-RPC 可为 0）
  u32 dst       = 目标虚拟 IP（广播包为 0xFFFFFFFF）
  [payload]
  ```

- 数据批量：每 tick（约 8ms）把到同一目标、同类型的多个 IP 包聚合成一条消息，
  控制 Steam 每秒消息数上限；单条消息上限 32KB，超过就拆多条。
- 可靠性：
  - IP 包 → `UNRELIABLE | NO_NAGLE`，丢包交给 TCP / 游戏协议；
  - 控制与 AppRPC → `RELIABLE`；
  - 不自建重传，SDR 已处理加密与链路重传。
- 延迟驱动：Steam 回调只在 `run_callbacks` 时产生，tick 上界 8ms；TUN 有包时通过
  channel 立即唤醒，避免固定 sleep 的抖动。

## 虚拟网卡与 IP

- 网卡：`wintun` crate（0.5.1）+ `dlls/wintun.dll`，适配器名 `AstralSteam`。
  L3 网卡，MTU 1280（避免分片；TCP 会自动按 MTU 分片）。
- 网段：沿用 `kRoomDhcpIpv4Cidr = 100.100.100.0/24`；房主 `100.100.100.1`，
  客人从 `.2` 起按最小空位分配。第一版只配 IPv4，不设默认网关。
- 配置方式：`netsh interface ipv4 set address name=<适配器> static <vip> 255.255.255.0`
  + 复用现有 `set_interface_metric_blocking` 把跃点压到 0。
- 关闭 DHCP / 固定 IP：第一版 Steam 模式只支持自动分配，设置页隐藏固定 IP 选项。

## 数据面路径

- 上行：wintun 阻塞读线程 → `mpsc` → Steam tick 线程 → 目标 NetConnection。
- 下行：Steam 收到帧 → 校验 → `session.allocate_send_packet` + `send_packet` 写回 TUN。
- 目标判定：
  - 目的虚拟 IP 属于本房间成员 → 单播（客人发给房主，由房主再转发）；
  - `255.255.255.255`、子网广播、`224.0.0.0/4` → 泛洪给除来源外的所有成员；
  - 其它地址 → 丢弃，并在状态里计数，避免把 Steam 当出口代理。
- 环路与重复：星型下广播只经过房主一跳；仍用 `flood_id` + `(src, 帧哈希)` 短期缓存去重。

## 局域网发现

只保留 TUN 内广播/组播的泛洪路径：游戏把发现包发到虚拟网卡后，由数据面按泛洪
送达所有成员，成员写入 TUN 时源地址即发送方虚拟 IP，游戏看到的是“局域网里的
某台机器”。

- 不做物理网卡旁路监听，也不维护游戏规则组；
- 因此不会出现“端口桥接/发现旁路”条目，也不依赖游戏是否在物理网卡上收发广播。

## 房间协议（控制通道）

| 消息 | 方向 | 说明 |
|------|------|------|
| `Hello` | 客 → 房主 | `join_token`（复用房间 `networkSecret`）、SteamID、昵称、版本 |
| `Welcome` | 房主 → 客 | 分配的虚拟 IP、房主虚拟 IP、网段、MTU |
| `Roster` | 房主 → 全员 | 成员表：SteamID、昵称、虚拟 IP、状态、直连/中继 |
| `Ping/Pong` | 双向 | 心跳与延迟测量，超时判离线和触发重连 |
| `Bye` | 双向 | 主动离开 |
| `Kick` | 房主 → 客 | 房主拒绝连接（目前仅用于 `join_token` 不匹配） |

- 鉴权：房主校验 `join_token`；vport 对同 AppID 的所有 Steam 用户可见，
  因此 token 必须命中，否则拒绝并关闭连接。
- 重连：Steam 连接状态 + 心跳；重新 `Hello` 后尽量分回原虚拟 IP（房主保留 30s 宽限）。
- 成员上限建议 8（星型下房主上行 ≈ 成员数 × 游戏流量）。

## 应用内 RPC 对等

`PeerRpcClient` / `PeerRpcRouter` 的接口不变，底层加传输后端：

- EasyTier 后端：现有 `appCall` / `appNotify` / `subscribeAppInbound`。
- Steam 后端：`steamAppCall` / `steamAppNotify` / `steamSubscribeAppInbound` /
  `steamAppCallReply` / `steamPeerPing`，通道、`request_id`、payload 字节保持不变。
- 成员需要一个稳定的 `u32 peer_id`：由房主在 Roster 里分配（`1..N`），
  与 SteamID 一一对应；Dart 侧不用感知 SteamID。
- 这样开播游戏列表、资料/头像、心跳等业务逻辑完全复用。

## Steam 相关约束

- 开发期 AppID **480**（`Client::init_app` 会设置 `SteamAppId`，无需 `steam_appid.txt`；
  可用 `ASTRAL_STEAM_APPID` 覆盖）。正式发行必须真实 AppID，并在 Steamworks 后台
  启用 SDR / P2P，否则线上不可用。
- 同一账号 + 同一台机器会被 Steam 降级成本地 “pipe”，**无法验证中继路径**；
  端到端验证需要两台机器或两个账号。
- 中继/直连由 Steam 决定，应用只展示，不干预。
- SDR 中继有流量成本/配额；需要观察大流量游戏的速率与丢包。
- Steam 客户端必须运行且已登录；初始化失败要有明确提示并可重试。
- `steamworks` 依赖必须放在 `[target.'cfg(target_os = "windows")'.dependencies]`，
  否则 Android/Linux 构建会因 `steamworks-sys` 不支持而失败。

## Dart 侧接入

- `TransportMode` 增加 `steam`；设置页开关、`SteamTransportPanel` 保留，文案改为
  “虚拟局域网 / SDR”。
- `ConnectionService`：
  - 建房：`steamStart(host: true, joinToken, ...)`，payload 带 `transport: steam` +
    `hostSteamId`；
  - 进房：按 payload 的 `hostSteamId` 调 `steamStart(host: false, ...)`；
  - 断开：`steamStop()`。
  - Steam 分支跳过 EasyTier 的 TOML、TUN 等待、服务器连通检查。
- `NodeManagementService`：新增 Steam 轮询源，把 Rust 的成员快照映射成现有 `KVNodeInfo`。
- `PeerRpcClient`：`bind` 时按传输模式选择后端。
- 会话/邀请：只保留 `transport` + `hostSteamId`；旧的 `steamTcpPorts` 等字段移除或忽略。

## 代码结构

| 文件 | 处理 |
|------|------|
| `rust/src/api/steam.rs` | 保留为跨平台门面，新增组网 API |
| `rust/src/api/steam_impl.rs` | **删除端口桥接**（已移除），发现旁路不再实现 |
| `rust/src/steam_tunnel/*` | 新增：proto / tun / engine |
| `lib/data/services/steam_transport_service.dart` | 改为组网启动/停止/状态 |
| `lib/data/models/steam_game_rule.dart` | **已删除**（规则组不再存在） |
| `docs/steam-direct-mode.md` | 本文件 |

## 分阶段验收

1. **P1 可玩**：一台房主、一台客人；虚拟 IP 互 ping 通；Minecraft 在局域网列表可见并能进服。
2. **P2 对等**：成员/延迟/流量可见；开播游戏、资料、房主操作与 EasyTier 模式一致；断线重连。
3. **P3 可选**：全网状直连（降低延迟）、IPv6、非 Windows 平台。

## 已知限制

- 第一版星型：延迟多一跳，房主上行随人数增长。
- Windows 专属；非 Windows 返回“不支持”。
- 只靠 TUN 泛洪做局域网发现：游戏若只往物理网卡发发现包，则需用虚拟 IP 直连。
- Steam 模式与 EasyTier 模式的虚拟网段相同，不能同时启用两个房间实例。
