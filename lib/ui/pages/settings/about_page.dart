import 'package:astral_game/config/app_dimensions.dart';
import 'package:astral_game/config/constants.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/utils/app_version.dart';
import 'package:astral_game/utils/client_runtime_info.dart';
import 'package:astral_game/data/state/update_state.dart';
import 'package:astral_game/data/services/update_service.dart';
import 'package:astral_game/ui/widgets/astral_card.dart';
import 'package:astral_game/ui/widgets/astral_grouped_tile.dart';
import 'package:astral_game/ui/widgets/astral_settings_section.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// 关于页。无内部可变状态，直接使用同步版本号。
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final updateState = getIt<UpdateState>();
    final updateService = getIt<UpdateService>();
    final currentVersion = ClientRuntimeInfo.appVersion;

    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppDimensions.pagePaddingH,
          AppDimensions.pagePaddingV,
          AppDimensions.pagePaddingH,
          24,
        ),
        children: [
          AstralCard(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
                  child: Image.asset(
                    'assets/logo.png',
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Astral Game',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 4),
                Watch((context) {
                  final latestVersion = updateState.latestVersion.value;
                  final hasNew =
                      latestVersion != null &&
                      latestVersion.isNotEmpty &&
                      AppVersion.isNewer(latestVersion, currentVersion);
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'v$currentVersion',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      if (hasNew) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '新版本: $latestVersion',
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                }),
                const SizedBox(height: 4),
                Text(
                  'Astral 游戏客户端',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppDimensions.sectionGap),
          AstralSettingsFormCard(
            rows: [
              (index, count) => AstralGroupedTile(
                icon: Icons.update_outlined,
                label: '检查更新',
                index: index,
                count: count,
                onTap: () => updateService.checkForUpdates(context),
                trailing: Watch((context) {
                  if (updateState.isChecking.value) {
                    return const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    );
                  }
                  return const Icon(Icons.chevron_right_rounded);
                }),
              ),
              (index, count) => AstralGroupedTile(
                icon: Icons.download_outlined,
                label: '前往下载',
                subtitle: 'next.astral.fan/game',
                index: index,
                count: count,
                onTap: () => updateService.openDownloadPage(),
                trailing: const Icon(Icons.open_in_new, size: 18),
              ),
              (index, count) => AstralGroupedTile(
                icon: Icons.link_outlined,
                label: 'GitHub',
                subtitle: 'AstralNext/AstralGame',
                index: index,
                count: count,
                onTap: () => _launchUrl(AppConstants.githubRepoPage),
                trailing: const Icon(Icons.open_in_new, size: 18),
              ),
              (index, count) => AstralGroupedTile(
                icon: Icons.bug_report_outlined,
                label: '反馈问题',
                subtitle: 'AstralGame Issues',
                index: index,
                count: count,
                onTap: () => _launchUrl(AppConstants.githubIssuesPage),
                trailing: const Icon(Icons.open_in_new, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
