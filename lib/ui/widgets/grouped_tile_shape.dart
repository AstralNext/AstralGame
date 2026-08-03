import 'package:astral_game/config/app_dimensions.dart';
import 'package:flutter/material.dart';

RoundedRectangleBorder groupedTileShape({
  required int index,
  required int count,
  double radius = AppDimensions.radiusLg,
}) {
  if (count <= 1) {
    return RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    );
  }
  if (index == 0) {
    return RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
    );
  }
  if (index == count - 1) {
    return RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(radius)),
    );
  }
  return const RoundedRectangleBorder();
}

BorderRadius groupedTileBorderRadius({
  required int index,
  required int count,
  double radius = AppDimensions.radiusLg,
}) {
  final r = Radius.circular(radius);
  if (count <= 1) return BorderRadius.all(r);
  if (index == 0) return BorderRadius.vertical(top: r);
  if (index == count - 1) return BorderRadius.vertical(bottom: r);
  return BorderRadius.zero;
}
