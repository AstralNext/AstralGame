import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

/// 图片选择工具类
class ImagePickerHelper {
  ImagePickerHelper._();

  /// 从相册选择图片，返回原始字节。
  ///
  /// 不做缩放：一旦带 maxWidth/maxHeight，插件会把图片重新编码成静态图，
  /// GIF / 动态 WebP 的动画会丢失。缩放交给头像编辑器处理。
  static Future<Uint8List?> pickImageFromGallery() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      return await image.readAsBytes();
    }
    return null;
  }
}
