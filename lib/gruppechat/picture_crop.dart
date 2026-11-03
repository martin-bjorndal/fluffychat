// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui' as ui;

import 'package:crop_image/crop_image.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// What a picture is cropped for.
enum PictureCrop {
  /// A profile picture or a chat's picture: square, and shown as a circle.
  avatar(maxSize: 1024),

  /// A chat background, which fills the screen.
  background(maxSize: 2560);

  /// The longest side of the cropped picture, in pixels.
  final double maxSize;

  const PictureCrop({required this.maxSize});
}

/// Shows how [bytes] will be cropped and lets the person move, resize and
/// turn the crop. Returns the cropped picture, or null if they went back.
Future<Uint8List?> showPictureCrop(
  BuildContext context, {
  required Uint8List bytes,
  required PictureCrop crop,
}) {
  final screen = MediaQuery.sizeOf(context);
  return Navigator.of(context).push<Uint8List>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => PictureCropPage(
        bytes: bytes,
        crop: crop,
        // A background is drawn at the screen's size, so it is cropped to
        // the screen's shape: what is inside the frame is what shows
        aspectRatio: crop == PictureCrop.avatar
            ? 1
            : screen.width / screen.height,
      ),
    ),
  );
}

/// Shows how a picture picked for a profile or a chat will be cropped and
/// lets the person adjust it. Returns it ready to upload, or null if they
/// went back.
Future<MatrixFile?> cropAvatar(BuildContext context, Uint8List bytes) async {
  final cropped = await showPictureCrop(
    context,
    bytes: bytes,
    crop: PictureCrop.avatar,
  );
  if (cropped == null) return null;
  return MatrixFile(
    bytes: cropped,
    name: croppedPictureName('avatar', cropped),
  );
}

/// [base] with the extension of a cropped picture's format.
String croppedPictureName(String base, Uint8List bytes) =>
    '$base.${_isPngBytes(bytes) ? 'png' : 'jpg'}';

bool _isPngBytes(Uint8List bytes) =>
    bytes.length > 4 &&
    bytes[0] == 0x89 &&
    bytes[1] == 0x50 &&
    bytes[2] == 0x4E &&
    bytes[3] == 0x47;

class PictureCropPage extends StatefulWidget {
  final Uint8List bytes;
  final PictureCrop crop;
  final double aspectRatio;

  const PictureCropPage({
    required this.bytes,
    required this.crop,
    required this.aspectRatio,
    super.key,
  });

  @override
  State<PictureCropPage> createState() => _PictureCropPageState();
}

class _PictureCropPageState extends State<PictureCropPage> {
  late final CropController _controller = CropController(
    aspectRatio: widget.aspectRatio,
  );
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _controller.getImage() == null) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      final image = await _controller.croppedBitmap(
        maxSize: widget.crop.maxSize,
      );
      final bytes = await _encode(image, keepTransparency: _isPng);
      image.dispose();
      navigator.pop(bytes);
    } catch (e, s) {
      Logs().w('Unable to crop the picture', e, s);
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  /// PNGs may be see-through, which JPEG would turn black.
  bool get _isPng => _isPngBytes(widget.bytes);

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.gruppechatAdjustPicture),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              tooltip: l10n.save,
              icon: const Icon(Icons.check),
              onPressed: _save,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            // Inset from the screen edges, so dragging a corner doesn't
            // start the system's back gesture
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 20.0,
                vertical: 12.0,
              ),
              child: CropImage(
                controller: _controller,
                image: Image.memory(widget.bytes),
                alwaysMove: true,
                overlayPainter: widget.crop == PictureCrop.avatar
                    ? _RoundGuidePainter(_controller)
                    : null,
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: l10n.rotateLeft,
                    icon: const Icon(Icons.rotate_left),
                    onPressed: _saving ? null : _controller.rotateLeft,
                  ),
                  Expanded(
                    child: Text(
                      l10n.gruppechatAdjustPictureHint,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.rotateRight,
                    icon: const Icon(Icons.rotate_right),
                    onPressed: _saving ? null : _controller.rotateRight,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Darkens the corners of the crop outside its circle, which is the part of
/// a profile picture that people see.
class _RoundGuidePainter extends CustomPainter {
  final CropController controller;

  _RoundGuidePainter(this.controller) : super(repaint: controller);

  @override
  void paint(Canvas canvas, Size size) {
    final crop = controller.crop;
    final rect = Rect.fromLTRB(
      crop.left * size.width,
      crop.top * size.height,
      crop.right * size.width,
      crop.bottom * size.height,
    );
    final circle = Path()..addOval(rect);
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(rect), circle),
      Paint()..color = Colors.black54,
    );
    canvas.drawPath(
      circle,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_RoundGuidePainter oldDelegate) =>
      oldDelegate.controller != controller;
}

/// The cropped picture as PNG when it may be see-through, otherwise as
/// JPEG, which is far smaller for photos.
Future<Uint8List> _encode(
  ui.Image image, {
  required bool keepTransparency,
}) async {
  final format = keepTransparency
      ? ui.ImageByteFormat.png
      : ui.ImageByteFormat.rawRgba;
  final data = await image.toByteData(format: format);
  if (data == null) throw Exception('Could not read the cropped picture');
  final bytes = data.buffer.asUint8List();
  if (keepTransparency) return bytes;
  return compute(_jpegFromRgba, (bytes, image.width, image.height));
}

Uint8List _jpegFromRgba((Uint8List, int, int) picture) {
  final (rgba, width, height) = picture;
  final image = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgba.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return img.encodeJpg(image, quality: 88);
}
