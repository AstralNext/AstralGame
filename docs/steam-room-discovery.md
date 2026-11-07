# Steam 房间发现与按游戏隔离（规范草案）

> 状态：草案，**未实现**。实现（阶段三）需等三条产品决策到齐后再动。
>
> **重要前提：「按游戏隔离」不等于「有房间列表」。**
> 当前代码里没有任何 Steam Lobby / 房间发现逻辑。要做公共搜房，是**新建一个子系统**，不是给现有功能加一个过滤条件。读本文时不要把「按游戏隔离」理解成已有列表的字段筛选。

## 1. 现状事实

| 事实 | 证据 |
|---|---|
| 全仓库没有 Steam Matchmaking Lobby 代码 | `rust/src` 与 `lib/` 中无 lobby / matchmaking 调用 |
| 房间发现只有邀请：短码或离线邀请，拿到 `hostSteamId + networkSecret` 后直连 | `lib/data/services/connection_service.dart:384-444`、`lib/utils/room_share.dart` |
| P2P 虚拟端口对**同 AppID 的所有 Steam 用户**可见 | `docs/steam-direct-mode.md` |
| 当前 AppID 默认 480（Spacewar），同类测试应用多，公共区更混杂 | `rust/src/steam_tunnel/engine.rs` `resolve_appid()` |

所以「房会和别人的房混在一起」的根因不是列表没过滤，而是**我们根本还没有列表**；一旦引入 Lobby，公共区就是同 AppID 的全部玩家。

## 2. 能力结论：用 lobby data key，不用房名前缀

`rust/vendor/steamworks/src/matchmaking.rs` 已提供完整能力，Steam 的「房间标签」就是 lobby 的 key-value 元数据：

| 能力 | 方法 | 用途 |
|---|---|---|
| 创建公开大厅 | `create_lobby(LobbyType::Public)` | 建房 |
| 写/读标签 | `set_lobby_data` / `lobby_data` / `lobby_data_count` | 写入游戏标识、门槛类型、显示名 |
| 枚举标签 | `lobby_data_by_index` | 搜房后本地二次校验 |
| 服务端字符串过滤 | `add_request_lobby_list_string_filter` | `ag_game == 本游戏` |
| 数值/空位过滤 | `add_request_lobby_list_numerical_filter`、`set_request_lobby_list_slots_available_filter` | 人数上限筛选 |
| 可加入状态 | `set_lobby_joinable(false)` | 满员 / 锁定 / 已结束时从搜索结果移除 |
| 成员标签 | `set_lobby_member_data` / `get_lobby_member_data` | 仅同房可见的玩家标签 |
| 人数与房主 | `lobby_member_count` / `lobby_members` / `lobby_owner` | 权威判断房间是否还有人 |

边界：

- Steam 没有原生「标签数组」。多标签要么拆成多个 key（可参与服务端过滤），要么塞进一个分隔串（只能拉回本地过滤）。
- lobby 元数据有总量上限（Steam 常量 `k_cubChatMetadataMax`），只放短小公开字段。
- **密码、口令、可逆凭据一律不得写入 lobby name 或 lobby data。**

结论：房名前缀编码不成立——需要自行转义、易被截断、可被冒用，且只能本地解析。结构化 key 由 Steam 服务端过滤，成本和风险都更低。

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

规则：

- 所有 key 前缀 `ag_`，避免与别家应用冲突；未知 `ag_*` key 一律忽略，不报错。
- `ag_name` 不参与任何逻辑判断，解析失败也不影响进房。
- 写标签只在建房、门槛变化、人数变化时触发，不做高频刷新。

## 4. 三条路径

### 4.1 建房

1. `create_lobby(Public)`；
2. 依次写 `ag_game` / `ag_ver` / `ag_gate` / `ag_name`（可选 `ag_host` / `ag_cap`）；
3. 写完后 `set_lobby_joinable(true)`；
4. 保留现有 `hostSteamId + join_token` 直连通道，邀请照旧可用。

### 4.2 搜房

1. `request_lobby_list`，加 `ag_game == 本游戏` 的字符串过滤；
2. 结果逐条本地校验：`ag_ver` 匹配、`ag_gate` 合法、`lobby_data(ag_game)` 二次确认；
3. 任一不满足即丢弃，**不得进入列表**；
4. 再按 `lobby_member_count` 过滤满员房。

服务端过滤与本地校验必须同时存在：服务端过滤是性能手段，本地校验才是正确性保证。

### 4.3 进房

1. 先读 `lobby_data(ag_game)` 与本地游戏比对，不一致直接拒绝（防陈旧条目、防被改写）；
2. 再在 HELLO 里带 `game_id`，由房主二次校验；
3. 任一步失败给出明确错误，不静默改走 EasyTier。

这构成三层校验：服务端过滤 → 进房前 lobby data → HELLO 内 game_id。

## 5. 生命周期与「幽灵房」

- 房主关房顺序：`set_lobby_joinable(false)` → 通知成员 → `leave_lobby`。房主是唯一成员时大厅随即销毁。
- 列表侧仍必须有本地 TTL 兜底：Steam 回调可能延迟或丢失，不能只依赖事件。
- 这与问题 1（幽灵成员）的结论一致：**任何"列表"都必须有本地过期策略，不能只靠事件驱动。**

## 6. 两条路线（需要用户拍板，不默认选定）

| 路线 | 内容 | 代价 | 结果 |
|---|---|---|---|
| A. 大厅公共搜房 | 新增 lobby 子系统：建房写标签、搜房列表、进房校验 | 新增 Rust lobby 模块 + Dart 列表 UI + 生命周期管理 | 可公共发现；同 AppID 全员可见 |
| B. 只保留邀请直连 | 不引入 lobby，仅在 HELLO 里加 `game_id` 校验 | 改动极小 | 无法公共搜房；「按游戏隔离」退化为进房时的单点校验 |

本文不预设选择。若选 B，第 3、4.2 节作废，只保留 4.3 的 HELLO 校验。

## 7. 游戏标识从哪来（两方案对比）

### 方案 A：建房时手动选（当前模型）

- 现状：`createAndConnect(gameId: ..., gameName: ...)` 的 `gameId` 由 UI 选定，`_createSteamRoom` 直接使用。
- 代价：零改动。
- 风险：用户选错游戏 → 房间进错隔离区。可通过「当前游戏」预填 + 建房确认页降低。

### 方案 B：自动探测 Steam 当前运行的游戏

- 可行性：**在独立进程里拿不到**。`ISteamApps::GetAppID` 返回的是本进程自己的 AppID（当前默认 480），不是另一款游戏的 AppID；Steamworks 没有「查询其他正在运行游戏」的公开接口。
- 可行的替代路径（都需要新代码）：
  1. 枚举进程（`tasklist` / Toolhelp32），与 `steamapps/*/appmanifest_*.acf` 的 `installdir` / 可执行名匹配；
  2. 读取 Steam 安装目录下的运行状态标记（非官方接口，稳定性无保证）；
  3. 用户选择后记住映射（exe → game slug）。
- 代价：进程扫描与路径解析、非 Steam 游戏与反作弊兼容、误匹配处理，均需单独测试。
- 拿不到时的降级：回落到方案 A（手动选），并在 UI 明示「未能自动识别，请手动选择」。
- 结论：默认 A；B 作为后续增强，不阻塞本次隔离需求。

## 8. 公开房策略

- **默认强制至少基础密码**：`ag_gate` 只允许 `basic` / `double`。
- 无门槛公开房（`open`）必须由房主显式开启，并在建房确认页二次确认；列表中用明显标识区分。
- 是否需要 `open` 这一档，属于待拍板项（见第 6 节与产品三问）。

## 9. 房名前缀降级方案（不推荐）

保留格式定义，供选 B 或极端兼容场景使用：

```
AG1|<game>|<gate>|<display>
```

- 统一 `encodeRoomName` / `parseRoomName` 两个函数收口，禁止各处 `split`。
- 不推荐原因：需自定义转义（`|` 与中文显示名）、易被长度截断、可被伪造冒充、新增字段要改格式版本；且没有服务端过滤，只能全量拉回本地筛。
- 若启用，必须同时保留 lobby data key（若有），名字只作为兜底展示。

## 10. 测试计划

- Rust：标签写入/读取/本地校验的纯函数单测；未知 key 忽略；版本不符拒绝；陈旧条目拒绝。
- Dart：列表过滤（非本游戏、版本不符、满员、`ag_name` 异常）逐条断言；进房前 `game_id` 校验失败文案。
- 双账号：建房→搜房→进房全链路；改 `ag_game` 后确认不会进错房。
