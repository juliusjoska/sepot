import 'package:flutter/material.dart';

/// Obdélník, ze kterého se na iOS vysune okno sdílení (`sharePositionOrigin`).
///
/// Od iOS 26 má systémové okno sdílení popover i na iPhonu a share_plus bez
/// nenulového obdélníku uvnitř okna appky volání odmítne
/// (`PlatformException: sharePositionOrigin: argument must be set`) — okno se
/// vůbec neotevře. Na Androidu se hodnota ignoruje.
Rect shareOrigin(BuildContext context) {
  final box = context.findRenderObject();
  if (box is RenderBox && box.hasSize && !box.size.isEmpty) {
    return box.localToGlobal(Offset.zero) & box.size;
  }
  return Offset.zero & MediaQuery.sizeOf(context);
}
