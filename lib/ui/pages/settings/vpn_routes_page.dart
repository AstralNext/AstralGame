import 'package:astral_game/config/app_dimensions.dart';
import 'package:astral_game/data/services/app_settings_service.dart';
import 'package:astral_game/data/state/vpn_state.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/ui/widgets/astral_card.dart';
import 'package:astral_game/ui/widgets/empty_state_widget.dart';
import 'package:astral_game/utils/input_validator.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

/// Android：管理 VpnService 额外路由（不含对端子网代理）。
class VpnRoutesPage extends StatelessWidget {
  const VpnRoutesPage({super.key});

  Future<void> _persist(VpnState vpn) async {
    await getIt<AppSettingsService>().setCustomVpnRoutes(vpn.customRoutes.value);
  }

  Future<void> _editRoute(
    BuildContext context, {
    int? index,
    String initial = '',
  }) async {
    final controller = TextEditingController(text: initial);
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(index == null ? '添加 VPN 路由' : '编辑 VPN 路由'),
        content: Form(
          key: formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'CIDR',
              hintText: '例如 192.168.1.0/24',
              border: OutlineInputBorder(),
            ),
            validator: InputValidator.validateCidr,
            keyboardType: TextInputType.number,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() == true) {
                Navigator.of(ctx).pop(controller.text.trim());
              }
            },
            child: Text(index == null ? '添加' : '保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || !context.mounted) return;

    final vpn = getIt<VpnState>();
    if (index == null) {
      vpn.addCustomRoute(result);
    } else {
      vpn.updateCustomRoute(index, result);
    }
    await _persist(vpn);
  }

  Future<void> _deleteRoute(
    BuildContext context,
    int index,
    String cidr,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除路由'),
        content: Text('确定删除「$cidr」？下次进房后生效。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final vpn = getIt<VpnState>();
    vpn.removeCustomRoute(index);
    await _persist(vpn);
  }

  @override
  Widget build(BuildContext context) {
    final vpn = getIt<VpnState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('自定义 VPN 路由'),
        actions: [
          IconButton(
            tooltip: '添加',
            icon: const Icon(Icons.add),
            onPressed: () => _editRoute(context),
          ),
        ],
      ),
      body: Watch((context) {
        final routes = vpn.customRoutes.value;
        if (routes.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const EmptyStateWidget(
                    icon: Icons.route_outlined,
                    message: '尚未添加额外路由',
                    subtitle: '默认仍包含虚拟网段、组播与广播',
                  ),
                  const SizedBox(height: 16),
                  FilledButton.tonalIcon(
                    onPressed: () => _editRoute(context),
                    icon: const Icon(Icons.add),
                    label: const Text('添加路由'),
                  ),
                ],
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(
            AppDimensions.pagePaddingH,
            AppDimensions.pagePaddingV,
            AppDimensions.pagePaddingH,
            24,
          ),
          itemCount: routes.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final cidr = routes[index];
            return AstralCard(
              padding: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.lan_outlined),
                title: Text(cidr),
                subtitle: const Text('写入 Android VpnService'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: '编辑',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _editRoute(
                        context,
                        index: index,
                        initial: cidr,
                      ),
                    ),
                    IconButton(
                      tooltip: '删除',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _deleteRoute(context, index, cidr),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      }),
    );
  }
}
