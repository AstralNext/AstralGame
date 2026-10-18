# AstralGame UI 修复手册

> 适用范围：Flutter 客户端 UI（`lib/ui`、`lib/config`）
> 核心目标：消除服务器页“检测/刷新”按钮的悬空感，统一页面骨架、间距、状态表达与空状态。
> 使用方式：按 P0 → P1 → P2 顺序执行，每个修复项独立提交；每项做完对照“验收标准”。

---

## 1. 问题总览

| 优先级 | 问题 | 位置 | 修复项 |
| --- | --- | --- | --- |
| P0 | 服务器页右上角“检测”按钮孤立悬空、状态跳变、语义混淆 | `lib/ui/pages/servers/servers_main_page.dart` | 2 |
| P0 | 全站缺少统一页面头（标题 + 状态 + 操作） | 各一级 Tab 页面 | 2、3 |
| P0 | 600 断点硬编码、页面边距 12/16/24 混用 | `shell.dart`、`servers_main_page.dart`、`bookmarks_page.dart`、`settings_main_page.dart` | 4 |
| P1 | 状态只靠色条，延迟色硬编码 `Colors.orange`，弱文本用 `outline` | `servers_main_page.dart` | 5 |
| P1 | 手机隐藏服务器地址；桌面菜单点击区偏小；拦截项假禁用；侧滑/长按无提示 | `servers_main_page.dart` | 6 |
| P1 | 两套空状态组件并存；FAB 与空态 CTA 重复 | `empty_state.dart`、`empty_state_widget.dart` | 7 |
| P2 | 探测结果是模拟数据；编辑 URL 后旧结果不失效 | `server_probe_service.dart`、`server_state.dart` | 8 |
| P2 | 顶栏/底栏固定高度，大字模式有溢出风险 | `mobile_chrome_bar.dart`、`bottom_nav.dart`、`theme.dart` | 9 |

---

## 2. P0-1 服务器页：页头 + 固定尺寸刷新按钮（核心）

### 2.1 现象

- 手机端 48px 顶栏下方紧接着一行只有右侧一个 `FilledButton.tonalIcon`，像“第二层 AppBar 掉出来的按钮”。
- 桌面端同样没有标题，按钮孤零零贴右边。
- 点按后文案 `检测 → 检测中` 导致按钮宽度变化、左边缘横向移动；图标 18px 与 spinner 14px 尺寸不一致。
- 页面本身已有周期 ping，按钮又做“探测 + ping”，用户不知道两者的区别。
- 成功后无反馈，只有存在非 ET 服务器时才弹 SnackBar。
- 空列表时按钮消失，添加第一台服务器后突然出现。

### 2.2 根因

按钮本身没有错，错在它没有依附的页面骨架：

1. 页面没有标题/工具条，按钮被放在 `Row(mainAxisAlignment: end)` 里（`servers_main_page.dart:149-172`）。
2. 操作语义与“刷新/自动更新”重叠（`server_state.dart:156-162`、`:129-154`）。
3. 加载态同时改变宽度、图标尺寸和透明度。
4. 右上角胶囊与右下角 FAB 争夺同一视觉轴。

### 2.3 目标形态

```text
┌────────────────────────────────────────────┐
│ 服务器                       3 台 · 2 在线  [↻] │
│ 上次检测 12:30                              │
├────────────────────────────────────────────┤
│ ● 华东节点                          [switch] │
│   10.0.0.1 · 32ms · 在线                    │
└────────────────────────────────────────────┘
```

规则：

- 页头左侧永远是页面标题与状态摘要，右侧永远是固定 40×40 的图标按钮。
- 刷新按钮使用 `Icons.refresh_rounded`，与测速页保持一致。
- 探测中只替换图标为 18×18 spinner，按钮尺寸、位置不变。
- 手机端支持下拉刷新，和按钮走同一逻辑。

### 2.4 实施步骤

#### Step 1：新增通用页头组件

新建 `lib/ui/widgets/page_header.dart`：

```dart
import 'package:astral_game/config/theme.dart';
import 'package:flutter/material.dart';

/// 一级页面统一页头：左侧标题/摘要，右侧固定尺寸操作。
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.horizontalPadding = 16,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 12, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}
```

#### Step 2：给 `ServerStatusState` 增加“上次手动检测时间”

文件：`lib/data/state/server_state.dart`

```dart
final lastProbeAt = signal<DateTime?>(null);
```

在 `probeServers` 成功写入结果后追加：

```dart
serverProbes.value = nextProbes;
serverLatencies.value = nextLatencies;
lastProbeAt.value = DateTime.now();
```

不要把周期 ping 的时间写进这个字段，否则“上次检测”会永远显示“刚刚”。

#### Step 3：重写服务器页顶部区域

文件：`lib/ui/pages/servers/servers_main_page.dart`

把原来的 `Column` 顶部 `Padding + Row + FilledButton.tonalIcon` 替换为：

```dart
final lastProbeAt = _serverStatusState.lastProbeAt.value;
final onlineCount = servers
    .where((s) => statuses[s.id] == ServerStatus.online)
    .length;
final hPad = isNarrow
    ? AppDimensions.pagePaddingHMobile
    : AppDimensions.pagePaddingH;

return Column(
  children: [
    PageHeader(
      horizontalPadding: hPad,
      title: '服务器',
      subtitle: servers.isEmpty
          ? '还没有添加服务器'
          : '${servers.length} 台 · $onlineCount 在线 · '
                '${lastProbeAt == null ? '尚未检测' : '上次检测 ${_hhmm(lastProbeAt)}'}',
      actions: [
        IconButton(
          tooltip: anyProbing ? '正在检测' : '重新检测并测速',
          onPressed: anyProbing ? null : () => _handleProbe(context),
          style: IconButton.styleFrom(
            minimumSize: const Size(40, 40),
            fixedSize: const Size(40, 40),
            padding: EdgeInsets.zero,
          ),
          icon: anyProbing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded, size: 20),
        ),
      ],
    ),
    Expanded(
      child: RefreshIndicator(
        onRefresh: () => _handleProbe(context),
        child: ReorderableListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            hPad,
            4,
            hPad,
            AppDimensions.listBottomWithFab,
          ),
          // 其余参数保持不变
        ),
      ),
    ),
  ],
);
```

时间格式化辅助函数（避免引入 intl）：

```dart
String _hhmm(DateTime time) {
  final h = time.hour.toString().padLeft(2, '0');
  final m = time.minute.toString().padLeft(2, '0');
  return '$h:$m';
}
```

#### Step 4：空状态也保留页头

当前 `servers.isEmpty` 直接 `return EmptyState(...)`，导致页头消失。改为页头常驻：

```dart
Expanded(
  child: RefreshIndicator(
    onRefresh: () => _handleProbe(context),
    child: servers.isEmpty
        ? LayoutBuilder(
            builder: (context, constraints) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: constraints.maxHeight,
                  child: EmptyState(
                    icon: Icons.dns_outlined,
                    title: '暂无服务器',
                    subtitle: '先添加一台 EasyTier 服务器',
                    actionLabel: '添加服务器',
                    actionStyle: EmptyActionStyle.filled,
                    actionIcon: Icons.add,
                    onAction: () => showAddServerDialog(context),
                  ),
                ),
              ],
            ),
          )
        : ReorderableListView.builder(/* 原列表 */),
  ),
)
```

#### Step 5：空态与 FAB 二选一

规则：**空列表只显示空态 CTA，非空列表只显示 FAB**。

把 `build` 中的 `Scaffold` 包进 `Watch`，让 FAB 跟随服务器数量：

```dart
return Watch((context) {
  final hasServers = _serverState.servers.value.isNotEmpty;
  return Scaffold(
    body: _buildBody(context, visible: visible),
    floatingActionButton: hasServers
        ? FloatingActionButton(
            heroTag: 'add_server',
            tooltip: '添加服务器',
            onPressed: () => showAddServerDialog(context),
            child: const Icon(Icons.add),
          )
        : null,
  );
});
```

#### Step 6：检测完成反馈

推荐只依赖页头摘要变化（`上次检测 HH:mm`），不弹成功提示。若产品坚持要反馈，只在“全部完成且无警告”时：

```dart
showAppToast(context, '检测完成', duration: const Duration(milliseconds: 1500));
```

非 ET 服务器的警告保持现状，但需先完成第 8 节的真实性处理。

### 2.5 验收标准

- [ ] 320/360/393 宽度下，页头标题、摘要、按钮不重叠、不溢出。
- [ ] 刷新按钮任何状态都是 40×40，位置不移动。
- [ ] 探测中按钮仅图标替换为 18×18 spinner，无宽度跳变。
- [ ] 空列表时页头仍在，FAB 隐藏；添加第一台服务器后 FAB 出现且无整页跳动。
- [ ] 手机下拉可触发检测；桌面按钮可触发检测。
- [ ] 检测完成后“上次检测”时间更新。
- [ ] 周期 ping 不会刷新“上次检测”时间。

---

## 3. P0-2 统一页面骨架

### 3.1 决策

- `MobileChromeBar` / `DesktopTitleBar` 只负责应用身份、头像、搜索，不塞页面标题。
- 每个一级 Tab 自己使用 `PageHeader`，这样标题、数量、操作、副标题都在同一行，且可随页面状态变化。
- 二级页继续使用标准 `AppBar`（如测速页），不要改成 `PageHeader`。

### 3.2 迁移顺序

1. 服务器页（本手册第 2 节）——必须做。
2. 设置页：在 `ListView` 顶部加 `PageHeader(title: '设置')`，移除等价的顶部留白。
3. 收藏页：加 `PageHeader(title: '收藏')`，摘要显示 `N 个房间`；搜索仍留在顶栏。
4. 联机页：已有自己的视觉重心，暂不强加页头，但左右边距必须走第 4 节 token。

### 3.3 验收标准

- [ ] 四个 Tab 切换时，内容区左右边界一致。
- [ ] 手机顶栏不再承担“页面标题”职责，也不会与页头标题重复。
- [ ] 页面滚动时页头保持固定，不随列表滚走（除非产品明确要求）。

---

## 4. P0-3 断点与间距统一

### 4.1 新增 token

文件：`lib/config/app_dimensions.dart`

```dart
/// 全站统一断点。
abstract final class AppBreakpoints {
  static const double narrow = 600;
}

abstract final class AppDimensions {
  // 原有 token 保留
  static const pagePaddingH = 24.0;
  static const pagePaddingV = 20.0;
  static const sectionGap = 16.0;

  // 新增
  static const pagePaddingHMobile = 16.0;
  static const pagePaddingBottom = 24.0;
  static const listBottomWithFab = 88.0;
}
```

### 4.2 替换硬编码

1. `lib/data/services/screen_state_service.dart`：
   `static const double _narrowThreshold = AppBreakpoints.narrow;`
2. `lib/ui/shell/shell.dart:300`：
   `final isCompact = screenWidth < AppBreakpoints.narrow;`
3. `lib/ui/pages/servers/servers_main_page.dart:145`：
   使用 `ScreenStateService.isNarrow` 或 `AppBreakpoints.narrow`，不要写 `600`。
4. `lib/ui/pages/bookmarks_page.dart:115`：
   同样替换 `>= 600`。

### 4.3 边距规则

| 场景 | 窄屏（<600） | 宽屏（≥600） |
| --- | --- | --- |
| 页面左右 | `pagePaddingHMobile` (16) | `pagePaddingH` (24) |
| 页面顶部 | 页头自带 12 | 页头自带 12 |
| 页面底部（无 FAB） | `pagePaddingBottom` (24) | 同左 |
| 页面底部（有 FAB） | `listBottomWithFab` (88) | 同左 |

服务器页当前窄屏 12 改为 16；设置页窄屏 24 改为 16；收藏页窄屏 16 保持不变。

### 4.4 验收标准

- [ ] 全仓库搜索 `< 600` / `>= 600`，除 token 定义外无残留。
- [ ] 服务器、收藏、设置三页在 599/600/601 宽度切换时无突兀跳变。
- [ ] 列表最后一项不会被 FAB 遮挡。

---

## 5. P1-1 状态颜色与文本语义

### 5.1 延迟颜色

`servers_main_page.dart:50-54` 的 `Colors.orange` 改为语义色：

```dart
Color _getLatencyColor(int latencyMs) {
  if (latencyMs <= 80) return AppColors.online;
  if (latencyMs <= 160) return AppColors.warning;
  return AppColors.error;
}
```

### 5.2 弱文本颜色

所有作为“说明文字”的 `colorScheme.outline` 改为：

```dart
final palette = context.astralPalette;
color: palette.textSecondary,
```

涉及：服务器地址、延迟文本、探测状态行。`outline` 只用于边框/分隔线。

### 5.3 状态不能只靠颜色

新增状态文案，并显示在延迟同一行：

```dart
String _statusLabel(ServerStatus status) => switch (status) {
  ServerStatus.online => '在线',
  ServerStatus.offline => '离线',
  ServerStatus.inUse => '使用中',
  ServerStatus.unknown => '未检测',
};
```

展示规则：

- `probing == true`：`检测中…`
- `latency != null`：`32ms · 在线`
- `latency == null && status == unknown`：`-- · 未检测`
- `inUse`：`-- · 使用中`

给整张卡片补无障碍语义：

```dart
Semantics(
  label: '${server.name}，${_statusLabel(status)}，'
      '延迟 ${latency == null ? '未知' : '$latency 毫秒'}',
  child: card,
)
```

### 5.4 验收标准

- [ ] 浅色与深色主题下，地址/延迟/探测文案对比度足够。
- [ ] 关闭颜色后仍能通过文字区分在线、离线、使用中。
- [ ] 延迟三档颜色在 7 套色板下观感一致。

---

## 6. P1-2 服务器卡片与操作可发现性

### 6.1 手机显示可辨识地址

不要再整体隐藏地址。手机显示 host，只有名称与地址完全相同时才省略：

```dart
final rawAddress = addressLine == '***'
    ? '***'
    : (Uri.tryParse(addressLine)?.host ?? addressLine);
final displayAddress = rawAddress.trim();
final showAddress =
    displayAddress.isNotEmpty &&
    displayAddress.toLowerCase() != server.name.trim().toLowerCase();
```

### 6.2 桌面“更多”按钮

`servers_main_page.dart:347-350` 的点击区只有 28×28。改为：

```dart
SizedBox(
  width: 40,
  height: 40,
  child: PopupMenuButton<String>(
    tooltip: '更多操作',
    iconSize: 20,
    padding: EdgeInsets.zero,
    onSelected: /* 原逻辑 */,
    itemBuilder: /* 原逻辑 */,
  ),
)
```

### 6.3 拦截项真正禁用

`_serverMenuItems` 中“编辑”项：

```dart
PopupMenuItem(
  value: 'edit',
  enabled: !isBlocked,
  child: /* 原内容 */,
)
```

### 6.4 侧滑与排序提示

- 手机卡片加 `Semantics(hint: '右滑编辑，左滑删除，长按拖动排序')`。
- 首次进入服务器页时用一次性 SnackBar 或页头副标题提示，不要每次弹。
- 如果产品不愿意加提示，至少在“更多”菜单中保留编辑/删除入口作为兜底。

### 6.5 验收标准

- [ ] 手机端两个重名服务器可通过地址区分。
- [ ] 桌面端“更多”按钮点击区 ≥ 40×40。
- [ ] 被拦截服务器的“编辑”项不可点击。
- [ ] 侧滑/长按有可被读屏软件读到的提示。

---

## 7. P1-3 空状态统一

### 7.1 决策

保留 `EmptyState`（`lib/ui/widgets/empty_state.dart`），删除 `EmptyStateWidget`。

### 7.2 迁移映射

| 旧 `EmptyStateWidget` | 新 `EmptyState` |
| --- | --- |
| `message` | `title` |
| `subtitle` | `subtitle` |
| `icon` | `icon` |
| 无操作 | `actionLabel` / `onAction` 可选 |

已知调用点：

- `lib/ui/pages/settings/speed_test_page.dart:79`
- `lib/ui/pages/settings/speed_test_page.dart:1250`
- `lib/ui/pages/settings/vpn_routes_page.dart:124`
- `lib/ui/widgets/user_list_widget.dart:28`

全部迁移后删除 `lib/ui/widgets/empty_state_widget.dart`。

### 7.3 统一规则

- 空状态必须有标题；副标题用于解释原因；操作按钮只在存在明确下一步时出现。
- 页面级空状态居中；列表内局部空状态不抢占整页高度。
- 同一页面不得同时出现空态 CTA 和 FAB 两个“添加”入口（见 2.4 Step 5）。

### 7.4 验收标准

- [ ] 全仓库无 `EmptyStateWidget` 引用。
- [ ] 空状态图标尺寸、标题字号、按钮样式一致。
- [ ] 服务器页空态、收藏页空态、测速页空态的垂直节奏一致。

---

## 8. P2-1 探测数据可信度与缓存

### 8.1 当前问题

`lib/data/services/server_probe_service.dart:26-77` 是模拟实现：按 URL 哈希生成“是否 ET / 版本号 / 提交号”。界面展示的 `EasyTier 2.7.0-xxxx` 与“非 EasyTier 服务器”并非真实握手结果。

### 8.2 处理方案（按优先级）

1. **短期（推荐）**：在真实握手实现前，不展示伪造版本号。
   - 删除卡片上的 `EasyTier x.y.z-commit · 协议 vN` 行。
   - 保留 `TCP ping` 延迟与在线/离线状态。
   - 删除 `_handleProbe` 中的“非 ET 服务器”SnackBar，或改为“兼容性检测暂不可用”。
2. **中期**：按 `ServerProbeService` 注释实现真实 EasyTier TCP 握手，校验魔数 `0xd1e1a5e1`，再恢复版本展示。
3. **如果必须保留模拟数据**：所有相关文案追加“（模拟）”，且不得据此给出风险警告。

### 8.3 编辑 URL 后清除旧探测结果

`serverProbes` 以 `server.id` 为 key，编辑 URL 不会改变 id，旧结果会残留。

在 `ServerStatusState` 中新增：

```dart
final Map<int, String> _probedUrls = {};

/// 服务器 URL 变化后丢弃对应的旧探测结果。
void invalidateStaleProbes(List<ServerMod> servers) {
  final currentUrls = {for (final s in servers) s.id: s.url};
  final nextProbes = Map<int, ServerProbeResult>.from(serverProbes.value);
  var changed = false;

  for (final id in nextProbes.keys.toList()) {
    if (currentUrls[id] != _probedUrls[id]) {
      nextProbes.remove(id);
      _probedUrls.remove(id);
      changed = true;
    }
  }
  if (changed) serverProbes.value = nextProbes;
}
```

在 `probeServers` 写入结果时记录 URL：

```dart
for (var i = 0; i < servers.length; i++) {
  nextProbes[servers[i].id] = results[i];
  nextLatencies[servers[i].id] = i < rtts.length ? rtts[i] : null;
  _probedUrls[servers[i].id] = servers[i].url;
}
```

在服务器页已有的 `fingerprint` 变化回调中调用（该回调本来就在 post-frame 里）：

```dart
WidgetsBinding.instance.addPostFrameCallback((_) {
  if (!mounted) return;
  _serverStatusState.invalidateStaleProbes(_serverState.servers.value);
  _serverStatusState.startPeriodicCheck(
    _serverState.servers.value,
    AppConstants.serverPingInterval,
  );
  _pingActive = true;
});
```

### 8.4 减少整页重建（可选）

`checkServersStatus` 每轮都整体替换两个 map（`server_state.dart:203-204`），会重建整页 `Watch`。服务器多时可以做浅比较，内容未变则不写 signal：

```dart
bool _sameStatusMap(Map<int, ServerStatus> a, Map<int, ServerStatus> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}
```

延迟 map 同理。此项不影响功能，放在最后做。

### 8.5 验收标准

- [ ] 编辑服务器 URL 后，卡片不再显示旧版本/旧兼容性信息。
- [ ] 未实现真实握手前，界面不存在伪造的 ET 版本号或误导性警告。
- [ ] 真实握手上线后，探测失败有明确错误态，不会静默显示“探测中”。

---

## 9. P2-2 固定高度与字体缩放

### 9.1 移动顶栏

`mobile_chrome_bar.dart:29-30` 的 `SizedBox(height: 48)` 改为最小高度：

```dart
ConstrainedBox(
  constraints: const BoxConstraints(minHeight: 48),
  child: Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: /* 原 Row */,
  ),
)
```

### 9.2 底部导航

`BottomNav` 固定 `height: 64/72`，`ThemeData.navigationBarTheme.height` 也固定 72。建议移除显式 height，让 `NavigationBar` 按内容与系统字号自行撑开；如必须限制，使用：

```dart
final scale = MediaQuery.textScalerOf(context).scale(1);
final height = 72 * scale.clamp(1.0, 1.3);
```

### 9.3 桌面标题栏

`DesktopTitleBar` 的 44px 固定高度同样改为 `minHeight: 44`，避免 Windows 放大字体时按钮溢出。

### 9.4 验收标准

- [ ] 系统字体缩放 1.0 / 1.3 / 2.0 下，顶栏、底栏、页头无 `RenderFlex overflow`。
- [ ] 底栏标签在 2.0 缩放下不被裁切；必要时自动隐藏标签。
- [ ] 桌面窗口最小宽度下，标题栏按钮仍可点击。

---

## 10. 提交拆分建议

按以下粒度提交，便于回滚与审查：

1. `ui(tokens): 统一断点与页面间距`
2. `ui(servers): 页头 + 固定尺寸刷新按钮 + 下拉刷新`
3. `ui(servers): 状态语义与卡片信息补全`
4. `ui(servers): 探测缓存失效与模拟数据标识`
5. `ui: 空状态组件统一`
6. `ui(shell): 字体缩放适配`

每提交一个，跑一次 `flutter analyze`；第 1、2 项完成后在真机上看一遍再继续。

---

## 11. 回归验收清单

### 尺寸

- [ ] 320 / 360 / 393 / 600 / 601 / 1024 / 1440 宽度
- [ ] 桌面窄窗口（<600）不出现“桌面标题栏 + 手机底栏”错位
- [ ] 横屏手机

### 字体与主题

- [ ] 字体缩放 1.0 / 1.3 / 2.0
- [ ] `insCream`（浅色）
- [ ] `darkCoffee` / `cyber2077`（深色）
- [ ] 主题切换动画结束后无残留色块

### 服务器页

- [ ] 空列表 → 添加 → 探测 → 编辑 URL → 删除
- [ ] 开关启用/禁用
- [ ] 长按拖动排序（手机）/ 鼠标拖动（桌面）
- [ ] 右滑编辑、左滑删除与取消
- [ ] 探测中退出页面再进入，状态能恢复
- [ ] 下拉刷新与右上角按钮行为一致
- [ ] 被拦截服务器不可编辑
- [ ] 读屏可读出名称、状态、延迟与操作提示

### 全站

- [ ] 收藏页搜索、分页、空态、无结果态
- [ ] 设置页各行点击与开关
- [ ] 测速页刷新、错误态、空态
- [ ] 手机安全区（刘海/底部手势条）

---

## 12. 命令

```bash
flutter analyze
flutter test
dart format lib test
flutter run -d windows
flutter run -d <android-device-id>
```

---

## 13. 约定与禁止事项

- 禁止再写死 `600`，统一使用 `AppBreakpoints.narrow`。
- 禁止在页面里写 `12/16/24` 之类的裸边距，统一走 `AppDimensions`。
- 禁止用 `colorScheme.outline` 当正文弱色，使用 `palette.textSecondary`。
- 禁止用裸 `Colors.orange` 等 Material 原色，使用 `AppColors` 语义色。
- 禁止同一页面出现两个“添加”主操作。
- 禁止在未实现真实握手时展示伪造的 EasyTier 版本号。
- 新组件优先复用 `PageHeader`、`EmptyState`、`AstralCard`、`AstralGroupedTile`。
