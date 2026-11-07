# Steam 房间双层密码（规范草案）

> 状态：草案，**未实现**。实现（阶段三）需等产品三问结论到齐后再动。
>
> 前置阅读：`docs/steam-room-discovery.md`。本文只定义认证，不定义搜房。

## 1. 目标与威胁模型

| 门 | 谁需要知道 | 挡谁 |
|---|---|---|
| 基础密码 | 拿到邀请的人 | 误入者、公开扫房者 |
| 额外密码 | 房主额外告知的人 | 知道基础密码的熟人、转发邀请的人 |

攻击者能力假设：能看到 lobby 公开数据与房间名；能拿到或截获邀请串；能录制并重放连接握手；能在线暴力尝试。**不在范围**：拥有 Steam 平台内部权限者、键盘记录器、房主本机被攻陷。

## 2. 两道门分工

| 项 | 基础密码 | 额外密码 |
|---|---|---|
| 来源 | 建房时随机生成，写入邀请（`networkSecret`） | 房主手动设置 |
| 是否进邀请 | 是（短码 / 离线邀请） | 否 |
| 是否进 lobby data | 否 | 否 |
| 校验位置 | 握手阶段，房主进程内 | 同一握手阶段 |
| 失败错误码 | 1 | 2 |
| 缺失时的行为 | 直接拒绝建房 | 允许不设，等价单密码房 |

## 3. 密码怎么传

### 3.1 原则

- 不明文出现在 HELLO / AUTH 载荷里；
- 不明文出现在 lobby `name` 或任何 lobby data；
- 不在日志、崩溃上报、本地设置文件里保存明文；
- 校验必须发生在 `assign_member` / `CTL_WELCOME` / 创建 wintun 之前。

### 3.2 挑战-响应流程

1. 客人建立 P2P 连接后**不直接发 HELLO**；房主对该连接发 `CTL_CHALLENGE { ver, nonce }`，`nonce` 为 16 字节随机数，**由房主生成**，一次性、5 秒过期。
2. 客人回 `CTL_AUTH { ver, game_id, steam_id, nickname, proof_basic[, proof_extra] }`：
   ```
   proof = HMAC-SHA256(password_hash, DOMAIN || nonce || host_steam_id || client_steam_id || game_id)
   ```
   - `password_hash` 是房主侧 `PBKDF2-HMAC-SHA256(password, salt, 150000)` 的结果；
   - 基础与额外密码各自独立计算 `proof_basic` / `proof_extra`，便于区分错误码。
3. 房主收到 AUTH 后用本地保存的 `salt + hash` 重算并**常量时间比较**。
4. 两项都通过才进入 `assign_member` → `CTL_WELCOME` → 建 wintun；任一失败立即回 `CTL_KICK { code }` 并断开。

为什么 nonce 必须由房主发：客户端自选 nonce 时，攻击者可录制「nonce + proof」整组数据重放；房主发的一次性 nonce 才能阻断重放。

### 3.3 基础密码的泄漏面与轮换

- **传输路径**：短码服务。`ShareCodeService.create` 会把整份 `RoomInvitePayload` JSON（含 `network_secret`）POST 给服务端（`lib/data/services/share_code_service.dart:122-131`）；离线邀请只是 Base64，不是加密（`lib/utils/room_share.dart:175-179`）。
- **因此基础密码会出现在**：短码服务端、聊天记录、剪贴板、截图、转发链。它只能承担「挡误入与公开扫房」，**不得复用用户常用密码**。
- **轮换**：每次建房重新生成 16 位随机口令；重新分享即轮换；房主「重置口令」后旧邀请的 `proof_basic` 不再匹配，旧邀请收到 `KICK code 1`。
- **建议（独立改造）**：短码服务端不持久化 `network_secret`，或改为只存哈希。属服务端范围，本文只记录为泄漏面。

### 3.4 额外密码

- 只在房主内存中保存 `salt + PBKDF2 hash`，重启后需重新输入或重新设置；
- 不写入邀请、不写入短码、不写入 lobby data；
- 通过房外渠道（口头、群聊）告知；
- 口令要求：至少 6 位、不强制字符类型，长度上限 64；房主设置时提示「额外密码只防熟人，不防暴力破解」。

## 4. 时序与连接状态机

```
Connected → Challenged → Authed → Welcome
```

- `Connected` / `Challenged` 阶段的连接**不得**进入 `conns` 转发表、不得分配虚拟 IP、不得出现在 roster、不得转发任何 IP 包或应用 RPC。
- 认证通过前，房主对该连接只接受控制层 AUTH 消息，其余帧一律丢弃。
- 与现状衔接：现有 `on_control` 的 `token` 校验已经发生在 `assign_member` 之前，改造时保持该顺序，把 token 校验替换为挑战-响应。
- 挑战发出后 5 秒未收到合法 AUTH：回 `KICK code 5` 并断开，**不依赖** 15 秒 `START_TIMEOUT`；客人端立即显示明确失败。

## 5. 错误码与文案

| code | 场景 | 客人端文案 | 可重试 |
|---|---|---|---|
| 1 | 基础密码错误 | 房间口令不正确，请向房主要最新邀请 | 是（重新输入） |
| 2 | 额外密码错误 | 额外密码不正确 | 是 |
| 3 | 房间已满 | 房间人数已满 | 否 |
| 4 | 版本不符 / 不支持双层密码 | 双方版本不一致，请升级到同一版本 | 否 |
| 5 | 认证超时 | 房主未响应认证，请确认网络后重试 | 是 |
| 6 | 房主关闭房间 | 房主已关闭房间 | 否 |

`Kick` 需携带 code；客人端按 code 映射文案，不再用「已加入失败」这类笼统提示，也不靠超时兜底。

## 6. 隐私

- lobby `name` 只放显示名，lobby data 只放 `ag_gate` 等公开字段；
- 日志与调试输出（含 `ASTRAL_STEAM_DEBUG`）不得打印密码、`proof`、`salt`；只允许打印 `code` 与 `steam_id`；
- 内存中的明文只在设置密码的瞬间存在，随后立即转 hash。

## 7. 兼容

- `CTL_CHALLENGE` / `CTL_AUTH` 带 `ver`；旧版客户端连新房主：房主 5 秒后 `KICK code 4`；
- 新版客户端连旧房主：收不到 CHALLENGE，超时后提示「房主版本过旧」；
- 不允许静默降级为单密码；降级必须由房主显式设置。

## 8. 测试计划

- Rust 纯函数单测：proof 计算与校验、常量时间比较、nonce 过期、重放拒绝、错误码映射。
- Rust 状态机单测：未认证连接不分配 VIP、不进 roster、不转发数据。
- Dart 单测：错误码 → 文案映射；`Kick` 到达时立即失败而非等待超时。
- 双账号：正确双层密码进房；基础错 / 额外错 / 超时 / 满员分别得到对应文案。
