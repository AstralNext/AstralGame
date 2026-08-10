import 'package:astral_game/config/app_dimensions.dart';
import 'package:astral_game/config/constants.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/utils/app_version.dart';
import 'package:astral_game/utils/client_runtime_info.dart';
import 'package:astral_game/data/state/update_state.dart';
import 'package:astral_game/data/services/update_service.dart';
import 'package:astral_game/ui/widgets/astral_card.dart';
import 'package:astral_game/ui/widgets/astral_settings_section.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _currentVersion = ClientRuntimeInfo.appVersion;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final version = await getIt<UpdateService>().getCurrentVersion();
    if (mounted) setState(() => _currentVersion = version);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final updateState = getIt<UpdateState>();
    final updateService = getIt<UpdateService>();

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
                final hasNew = latestVersion != null &&
                    latestVersion.isNotEmpty &&
                    AppVersion.isNewer(latestVersion, _currentVersion);
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'v$_currentVersion',
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
          children: [
            ListTile(
              leading: const Icon(Icons.update_outlined),
              title: const Text('检查更新'),
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
              onTap: () => updateService.checkForUpdates(context),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('前往下载'),
              subtitle: const Text('next.astral.fan/game'),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => updateService.openDownloadPage(),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.link_outlined),
              title: const Text('GitHub'),
              subtitle: const Text('AstralNext/AstralGame'),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => _launchUrl(AppConstants.githubRepoPage),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.bug_report_outlined),
              title: const Text('反馈问题'),
              subtitle: const Text('AstralGame Issues'),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => _launchUrl(AppConstants.githubIssuesPage),
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
