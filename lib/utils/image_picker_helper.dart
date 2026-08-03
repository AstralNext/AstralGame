import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

/// 图片选择工具类
class ImagePickerHelper {
  ImagePickerHelper._();

  /// 从相册选择图片
  static Future<Uint8List?> pickImageFromGallery({
    double maxWidth = 256,
    double maxHeight = 256,
  }) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
    );

    if (image != null) {
      return await image.readAsBytes();
    }
    return null;
  }
}
