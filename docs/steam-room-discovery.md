# Steam 房间发现与按游戏隔离（规范草案）

> 状态：草案，**未实现**。实现（阶段三）继续等待「游戏标识来源」「是否允许无门槛公开房」两条产品结论。
>
> 决策更新（本轮）：
> - Steam 路径**取消短码邀请**。短码只属于 EasyTier 通道，两条路不再共用邀请机制。
> - Steam 入口只有两个：**大厅搜房加入**、**Steam 好友邀请**。
> - **路线 A（走大厅）已确定**；路线 B「不做大厅、只留邀请直连」**已否决**（见第 6 节）。
>
> **重要前提：「按游戏隔离」不等于「有房间列表」。**
> 当前代码里没有任何 Steam Lobby / 房间发现逻辑。要做公共搜房，是**新建一个子系统**，不是给现有功能加一个过滤条件。

## 1. 现状事实

| 事实 | 证据 |
|---|---|
| 全仓库没有 Steam Matchmaking Lobby 代码 | `rust/src` 与 `lib/` 中无 lobby / matchmaking 调用 |
| 当前 Steam 房只能靠 `hostSteamId + join_token` 邀请直连 | `lib/data/services/connection_service.dart:384-444` |
| 短码服务承载 EasyTier 邀请载荷（含 `network_secret`） | `lib/data/services/share_code_service.dart:122-131` |
| P2P 虚拟端口对**同 AppID 的所有 Steam 用户**可见 | `docs/steam-direct-mode.md` |
| 当前 AppID 默认 480（Spacewar），同类测试应用多，公共区更混杂 | `rust/src/steam_tunnel/engine.rs` `resolve_appid()` |

注意：第 3 行是**现状**，本轮决策后 Steam 建房不再产生短码；短码链路只服务 EasyTier，不应再被 Steam 代码引用。

## 2. 能力结论：用 lobby data key，不用房名前缀

`rust/vendor/steamworks/src/matchmaking.rs` 已提供完整能力，Steam 的「房间标签」就是 lobby 的 key-value 元数据：

| 能力 | 方法 | 用途 |
|---|---|---|
| 创建公开大厅 | `create_lobby(LobbyType::Public)`（:86-112） | 建房 |
| 加入大厅 | `join_lobby(LobbyId, cb)`（:115-134），回调 `LobbyEnter` | 搜房后进房 / 接受好友邀请 |
| 大厅 ID 序列化 | `LobbyId::raw()`（:43-45） | 在 UI、回调、日志之间传值 |
| 写/读标签 | `set_lobby_data` / `lobby_data` / `lobby_data_count`（:142-192） | 游戏标识、门槛类型、显示名 |
| 枚举标签 | `lobby_data_by_index`（:136-178） | 搜房后本地二次校验 |
| 服务端字符串过滤 | `add_request_lobby_list_string_filter`（:390-405） | `ag_game == 本游戏` |
| 数值/空位过滤 | `add_request_lobby_list_numerical_filter`、`set_request_lobby_list_slots_available_filter`（:416-471） | 人数筛选 |
| 可加入状态 | `set_lobby_joinable`（:303-305） | 满员 / 锁定 / 已结束时从搜索结果移除 |
| 成员标签 | `set_lobby_member_data` / `get_lobby_member_data`（:200-239） | 仅同房可见的玩家标签 |
| 人数与房主 | `lobby_member_count` / `lobby_members` / `lobby_owner`（:262-292） | 判断房间是否还有人在 |

边界：Steam 没有原生「标签数组」，多标签需拆成多个 key；lobby 元数据有总量上限（`k_cubChatMetadataMax`），只放短小公开字段；**密码、口令、可逆凭据一律不得写入 lobby name 或 lobby data**。

## 3. 字段规范（`ag_` 命名空间）

| key | 必填 | 取值 | 长度建议 | 服务端过滤 | 说明 |
|---|---|---|---|---|---|
| `ag_game` | 是 | 稳定 ASCII slug，如 `scfa` | ≤ 32 | 是 | 游戏隔离的唯一依据 |
| `ag_ver` | 是 | 协议版本，如 `1` | ≤ 8 | 否 | 版本不符在进房前拒绝 |
| `ag_gate` | 是 | `basic` / `double` / `open` | ≤ 8 | 否 | 门槛类型；`open` 默认不产生 |
| `ag_name` | 是 | 房主起的显示名 | ≤ 48 字节 | 否 | 只做人类可读展示，不承载语义 |
| `ag_host` | 否 | 房主 SteamID | ≤ 20 | 否 | 与 `lobby_owner` 交叉校验 |
| `ag_players` | 否 | 当前人数 | ≤ 4 | 可选 | 仅展示 |
| `ag_cap` | 否 | 人数上限 | ≤ 4 | 可选 | 配合空位过滤 |

规则：未知 `ag_*` key 一律忽略；`ag_name` 解析失败不影响进房；标签只在建房、门槛变化、人数变化时写。

## 4. 入口与路径

Steam 只有两个入口：**大厅搜房**、**Steam 好友邀请**。

### 4.1 建房

1. `create_lobby(Public)`；
2. 写 `ag_game` / `ag_ver` / `ag_gate` / `ag_name`（可选 `ag_host` / `ag_cap`）；
3. `set_lobby_joinable(true)`；
4. **不生成短码**，不写入任何邀请载荷；
5. 保留 `hostSteamId` 作为连接目标，但只通过 lobby data（`ag_host`）或好友邀请传递，不再走短码。

### 4.2 搜房

1. `request_lobby_list`，加 `ag_game == 本游戏` 字符串过滤；
2. 结果逐条本地校验 `ag_ver` / `ag_gate` / `ag_game`；
3. 不满足即丢弃，**不得进入列表**；
4. 按 `lobby_member_count` 过滤满员房；
5. 用户选中后 `join_lobby`。

### 4.3 进房

1. 先读 `lobby_data(ag_game)` 与本地游戏比对，不一致直接拒绝；
2. 再在 HELLO 里带 `game_id`，由房主二次校验；
3. 任一步失败给出明确错误，不静默改走 EasyTier。

三层校验：服务端过滤 → 进房前 lobby data → HELLO 内 `game_id`。

### 4.4 Steam 好友邀请（能力核实）

结论：**能做，但只有「唤起原生邀请界面」和「邀请好友进入游戏」两种，缺少「程序化邀请指定好友进大厅」的封装。**

| 方式 | 封装情况 | 可行性 | 代价 |
|---|---|---|---|
| 原生好友邀请对话框 | `Friends::activate_invite_dialog(lobby_id)`（friends.rs:177-180，底层 `ActivateGameOverlayInviteDialog`） | 可用 | 依赖 Steam overlay 处于开启状态；不能程序化选好友，也拿不到「已邀请/已接受」状态；需要处理接收侧回调 |
| 邀请好友进入游戏 | `Friend::invite_user_to_game(connect_string)`（friends.rs:471-480） | 可用，但语义是「邀请进游戏」不是「邀请进大厅」 | 对方收到 `GameRichPresenceJoinRequested`；connect string 必须自带房主 SteamID 与游戏标识；**不经过 lobby data**，游戏隔离只能在 HELLO 做；对方未运行游戏时依赖启动参数拉起 |
| 邀请指定好友进大厅 | `InviteUserToLobby` **在 vendored crate 中不存在** | 需自行补 binding | 要改 `steamworks-sys` + 增加 wrapper，并承担上游升级时的维护成本 |

接收侧现状与缺口：

- `GameLobbyJoinRequested { lobby_steam_id, friend_steam_id }` 已有封装（friends.rs:269-279），`LobbyId::raw()` 可取 ID；
- `GameRichPresenceJoinRequested` 已有封装（friends.rs:281-305）；
- 但引擎当前只注册了 `SteamServersConnected` / `SteamServersDisconnected`（engine.rs 顶部 import），**没有注册任何 lobby / 邀请回调**，需要新增回调泵分支；
- 用户未启动本应用时，Steam 会用 `+connect_lobby <id>` 作为启动参数拉起进程；**当前没有任何命令行参数解析**，不加这段则「好友邀请」在应用关闭时静默无效。

推荐：首版用「原生邀请对话框 + `GameLobbyJoinRequested` + `+connect_lobby` 解析」，成本最低且与大厅数据天然一致；`invite_user_to_game` 作为无 overlay 环境的兜底，但必须接受「不走 lobby data」的隔离退化。

## 5. 生命周期与「幽灵房」

- 房主关房顺序：`set_lobby_joinable(false)` → 通知成员 → `leave_lobby`。房主是唯一成员时大厅随即销毁。
- 列表侧必须有本地 TTL 兜底：Steam 回调可能延迟或丢失，不能只依赖事件。
- 与问题 1（幽灵成员）的结论一致：**任何列表都必须有本地过期策略，不能只靠事件驱动。**

## 6. 路线结论

| 路线 | 结论 | 原因 |
|---|---|---|
| A. 大厅公共搜房 | **已确定** | Steam 入口只剩「搜房」与「好友邀请」，两者都以 lobby 为载体 |
| B. 只保留邀请直连 | **已否决** | 否决后没有搜房，与「Steam 靠搜索房间或好友邀请进入」的需求直接冲突 |

因此第 3、4.2 节为必做项，不再作为可选项讨论。

## 7. 游戏标识从哪来（仍待拍板）

### 方案 A：建房时手动选（当前模型）

- 现状：`createAndConnect(gameId: ..., gameName: ...)` 的 `gameId` 由 UI 选定。
- 代价：零改动。
- 风险：用户选错游戏 → 房间进错隔离区。可用「当前游戏」预填 + 建房确认页降低。

### 方案 B：自动探测 Steam 当前运行的游戏

- 可行性：**在独立进程里拿不到**。`ISteamApps::GetAppID` 返回本进程自己的 AppID（当前默认 480），Steamworks 没有查询其他正在运行游戏的公开接口。
- 可行替代路径（都需新代码）：枚举进程并与 `appmanifest_*.acf` 的 `installdir` / 可执行名匹配；读取 Steam 运行状态标记（非官方接口）；用户选择后记住映射。
- 代价：进程扫描与路径解析、非 Steam 游戏与反作弊兼容、误匹配处理，均需单独测试。
- 拿不到时降级：回落到方案 A，并明示「未能自动识别，请手动选择」。

结论：两条都留给用户拍板，本文不预设。

## 8. 公开房策略（仍待拍板）

- 默认建议：强制至少基础密码，`ag_gate` 只允许 `basic` / `double`。
- 若允许无门槛公开房（`open`），必须由房主显式开启并二次确认，列表用明显标识区分。
- 是否保留 `open` 这一档，等用户结论。

## 9. 房名前缀编码（已废弃）

原 `AG1|<game>|<gate>|<display>` 方案随路线 B 一起废弃：Steam 有结构化 key 与服务端过滤，名字前缀只会增加转义、截断、冒用成本。保留此节仅作决策记录，不再实现。

## 10. 测试计划

- Rust 纯函数单测：标签写入/读取/本地校验；未知 key 忽略；版本不符拒绝；陈旧条目拒绝。
- Dart：列表过滤（非本游戏、版本不符、满员、`ag_name` 异常）逐条断言；进房前 `game_id` 校验失败文案。
- 好友邀请：`GameLobbyJoinRequested` 回调 → 自动进房；应用未启动时 `+connect_lobby` 拉起后进房。
- 双账号：建房→搜房→进房全链路；改 `ag_game` 后确认不会进错房。
