import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

/// Opens the native share sheet for [text], anchoring the popover to [context]'s
/// widget. On iPad the share sheet is a popover and share_plus throws a
/// PlatformException ("sharePositionOrigin: argument must be set … must be
/// non-zero") if no origin rect is supplied — so always pass a sensible one.
/// Falls back to no origin (phones, where it's ignored) if the box isn't laid
/// out yet.
Future<void> shareText(
  BuildContext context,
  String text, {
  String? subject,
}) {
  final box = context.findRenderObject() as RenderBox?;
  final origin = (box != null && box.hasSize)
      ? box.localToGlobal(Offset.zero) & box.size
      : null;
  return Share.share(text, subject: subject, sharePositionOrigin: origin);
}
