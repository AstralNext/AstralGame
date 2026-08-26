import 'package:astral_game/utils/logger.dart';
import 'dart:io';
import 'dart:typed_data';

import 'package:astral_game/config/theme.dart';
import 'package:astral_game/data/services/alcy_wallpaper_service.dart';
import 'package:astral_game/data/services/hitokoto_service.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/utils/runtime_platform.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 每日风景卡：展示风景图 + 格言，支持下载。
///
/// 桌面端鼠标悬停展示下载按钮；移动端长按触发下载。
class DailySceneryCard extends StatefulWidget {
const DailySceneryCard({
super.key,
required this.username,
});

final String username;

@override
State<DailySceneryCard> createState() => DailySceneryCardState();
}

@visibleForTesting
class DailySceneryCardState extends State<DailySceneryCard> {
static const _fallbackAsset = 'assets/scenery/daily.jpg';

String _title = '';
String _subtitle = '';
String? _wallpaperUrl;
bool _textLoading = true;
bool _wallpaperRequested = false;
bool _downloading = false;
bool _hovering = false;

@override
void initState() {
super.initState();
_title = '欢迎，${widget.username}';
_subtitle = '准备好开一局了吗？';
_loadHitokoto();
}

@override
void didChangeDependencies() {
super.didChangeDependencies();
if (!_wallpaperRequested) {
_wallpaperRequested = true;
_loadWallpaper();
}
}

Future<void> _loadHitokoto() async {
try {
final quote = await getIt<HitokotoService>().fetch();
if (!mounted) return;
setState(() {
_title = quote.text;
_subtitle = quote.attribution.isNotEmpty
? quote.attribution
: '欢迎，${widget.username}';
_textLoading = false;
});
} catch (e) {
      appLogger.w('[SceneryCard] 操作失败', error: e);
if (!mounted) return;
setState(() => _textLoading = false);

    }
}

Future<void> _loadWallpaper() async {
final narrow = MediaQuery.sizeOf(context).width < 600;
try {
final url = await getIt<AlcyWallpaperService>().fetchImageUrl(
narrow: narrow,
);
if (!mounted) return;
setState(() => _wallpaperUrl = url);
} catch (e) {
      appLogger.w('[SceneryCard] 操作失败', error: e);
// 保留本地 fallback

    }
}

String _imageExt() {
final url = (_wallpaperUrl ?? '').toLowerCase();
if (url.contains('.png')) return '.png';
if (url.contains('.webp')) return '.webp';
if (url.contains('.gif')) return '.gif';
return '.jpg';
}

Future<Uint8List> _currentImageBytes() async {
final url = _wallpaperUrl?.trim();
if (url != null && url.isNotEmpty) {
final res = await http.get(Uri.parse(url)).timeout(
const Duration(seconds: 30),
);
if (res.statusCode < 200 || res.statusCode >= 300) {
throw StateError('图片下载失败：${res.statusCode}');
}
return res.bodyBytes;
}
final data = await rootBundle.load(_fallbackAsset);
return data.buffer.asUint8List();
}

bool _isPhoneLayout() {
if (!RuntimePlatform.isMobile) return false;
return MediaQuery.sizeOf(context).shortestSide < 600;
}

bool get _revealDownloadOnHover => RuntimePlatform.isDesktop;

bool get _downloadByLongPress => RuntimePlatform.isMobile;

Future<void> _downloadCurrentImage() async {
if (_downloading) return;
setState(() => _downloading = true);
HapticFeedback.mediumImpact();
try {
final bytes = await _currentImageBytes();
final name =
'astral-wallpaper-${DateTime.now().millisecondsSinceEpoch}${_imageExt()}';
if (_isPhoneLayout()) {
final tmp = await getTemporaryDirectory();
final file = File(p.join(tmp.path, name));
await file.writeAsBytes(bytes, flush: true);
await Share.shareXFiles([XFile(file.path)], text: 'Astral 壁纸');
return;
}
final ext = _imageExt().replaceFirst('.', '');
final path = await FilePicker.platform.saveFile(
dialogTitle: '保存壁纸',
fileName: name,
type: FileType.custom,
allowedExtensions: [ext],
bytes: bytes,
lockParentWindow: true,
);
if (path == null || path.isEmpty) return;
if (RuntimePlatform.isDesktop) {
await File(path).writeAsBytes(bytes, flush: true);
}
if (!mounted) return;
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
content: Text(
RuntimePlatform.isMobile ? '已保存' : '已保存到 $path',
),
),
);
} catch (e) {
      appLogger.w('[SceneryCard] 操作失败', error: e);
if (!mounted) return;
ScaffoldMessenger.of(context).showSnackBar(
const SnackBar(content: Text('下载失败')),
);

    } finally {
if (mounted) setState(() => _downloading = false);
}
}

Widget _buildBackground() {
final url = _wallpaperUrl;
if (url != null && url.isNotEmpty) {
// 限制解码分辨率，避免全分辨率壁纸占用内存。
final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 2;
final cacheW = (MediaQuery.sizeOf(context).width * dpr).round();
return Image.network(
url,
fit: BoxFit.cover,
gaplessPlayback: true,
cacheWidth: cacheW,
loadingBuilder: (context, child, progress) {
if (progress == null) return child;
return Image.asset(_fallbackAsset, fit: BoxFit.cover);
},
errorBuilder: (context, error, stackTrace) {
return Image.asset(
_fallbackAsset,
fit: BoxFit.cover,
errorBuilder: (context, error, stackTrace) {
return DecoratedBox(
decoration: BoxDecoration(
gradient: LinearGradient(
begin: Alignment.topLeft,
end: Alignment.bottomRight,
colors: [
context.astralPalette.accent.withValues(alpha: 0.55),
context.astralPalette.canvas,
],
),
),
);
},
);
},
);
}
return Image.asset(
_fallbackAsset,
fit: BoxFit.cover,
errorBuilder: (context, error, stackTrace) {
return DecoratedBox(
decoration: BoxDecoration(
gradient: LinearGradient(
begin: Alignment.topLeft,
end: Alignment.bottomRight,
colors: [
context.astralPalette.accent.withValues(alpha: 0.55),
context.astralPalette.canvas,
],
),
),
);
},
);
}

@override
Widget build(BuildContext context) {
final textTheme = Theme.of(context).textTheme;
final showDownloadButton =
_revealDownloadOnHover && (_hovering || _downloading);

Widget card = ClipRRect(
borderRadius: BorderRadius.circular(22),
child: Stack(
fit: StackFit.expand,
children: [
_buildBackground(),
const DecoratedBox(
decoration: BoxDecoration(
gradient: LinearGradient(
begin: Alignment.topCenter,
end: Alignment.bottomCenter,
colors: [
Color(0x00000000),
Color(0x66000000),
Color(0xB3000000),
],
stops: [0.35, 0.72, 1],
),
),
),
Positioned(
top: 10,
right: 10,
child: IgnorePointer(
ignoring: !showDownloadButton,
child: AnimatedOpacity(
duration: const Duration(milliseconds: 160),
opacity: showDownloadButton ? 1 : 0,
child: Material(
color: Colors.black.withValues(alpha: 0.38),
shape: const CircleBorder(),
clipBehavior: Clip.antiAlias,
child: IconButton(
tooltip: '下载当前图片',
onPressed: _downloading ? null : _downloadCurrentImage,
icon: _downloading
? const SizedBox(
width: 18,
height: 18,
child: CircularProgressIndicator(
strokeWidth: 2,
color: Colors.white,
),
)
: const Icon(
Icons.download_rounded,
color: Colors.white,
),
),
),
),
),
),
Positioned(
left: 20,
right: 20,
bottom: 20,
child: AnimatedOpacity(
duration: const Duration(milliseconds: 320),
opacity: _textLoading ? 0.55 : 1,
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
mainAxisSize: MainAxisSize.min,
children: [
Text(
_title,
style: textTheme.headlineSmall?.copyWith(
color: Colors.white,
fontWeight: FontWeight.w800,
letterSpacing: 0.2,
height: 1.2,
shadows: const [
Shadow(blurRadius: 12, color: Color(0x66000000)),
],
),
maxLines: 3,
overflow: TextOverflow.ellipsis,
),
const SizedBox(height: 8),
Text(
_subtitle,
style: textTheme.bodyMedium?.copyWith(
color: Colors.white.withValues(alpha: 0.88),
height: 1.35,
shadows: const [
Shadow(blurRadius: 8, color: Color(0x66000000)),
],
),
maxLines: 2,
overflow: TextOverflow.ellipsis,
),
],
),
),
),
],
),
);

if (_downloadByLongPress) {
card = GestureDetector(
behavior: HitTestBehavior.opaque,
onLongPress: _downloading ? null : _downloadCurrentImage,
child: card,
);
}

if (_revealDownloadOnHover) {
card = MouseRegion(
onEnter: (_) => setState(() => _hovering = true),
onExit: (_) => setState(() => _hovering = false),
child: card,
);
}

return card;
}
}
