import 'package:flutter/material.dart';
import 'package:astral_game/data/models/enhanced_node_info.dart';
import 'package:astral_game/ui/pages/dashboard_user_item.dart';
import 'package:astral_game/ui/widgets/empty_state_widget.dart';

class UserListWidget extends StatelessWidget {
  final List<EnhancedNodeInfo> users;
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  const UserListWidget({
    super.key,
    required this.users,
    this.shrinkWrap = false,
    this.physics,
  });

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) {
      return const EmptyStateWidget(
        icon: Icons.people_outlined,
        message: '暂无在线用户',
      );
    }

    return ListView.builder(
      shrinkWrap: shrinkWrap,
      physics: physics ?? const NeverScrollableScrollPhysics(),
      itemCount: users.length,
      itemBuilder: (context, index) {
        final node = users[index];
        return DashboardUserItem(
          key: ValueKey<int>(node.peerId),
          node: node,
        );
      },
    );
  }
}
