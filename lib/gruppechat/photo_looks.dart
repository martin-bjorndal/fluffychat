// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';
import 'dart:ui' as ui;

import 'package:fluffychat/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// A ready-made look for a photo, as in the photo editor's filter row.
enum PhotoLookPreset {
  original,
  blackWhite,
  sepia,
  warm,
  cool,
  vivid,
  faded,
  noir;

  String label(L10n l10n) => switch (this) {
    original => l10n.gruppechatLookOriginal,
    blackWhite => l10n.gruppechatLookBlackWhite,
    sepia => l10n.gruppechatLookSepia,
    warm => l10n.gruppechatLookWarm,
    cool => l10n.gruppechatLookCool,
    vivid => l10n.gruppechatLookVivid,
    faded => l10n.gruppechatLookFaded,
    noir => l10n.gruppechatLookNoir,
  };

  /// The colour matrix of this look (4×5, rows red, green, blue, alpha;
  /// the last column is an offset in 0–255, as [ColorFilter.matrix] takes).
  List<double> get matrix => _presetMatrices[index];

  static final _presetMatrices = [
    for (final preset in values) preset._computeMatrix(),
  ];

  List<double> _computeMatrix() => switch (this) {
    original => _identity,
    blackWhite => _saturation(0),
    sepia => const [
      0.393, 0.769, 0.189, 0, 0, //
      0.349, 0.686, 0.168, 0, 0, //
      0.272, 0.534, 0.131, 0, 0, //
      0, 0, 0, 1, 0,
    ],
    warm => const [
      1.1, 0, 0, 0, 10, //
      0, 1.0, 0, 0, 4, //
      0, 0, 0.85, 0, -10, //
      0, 0, 0, 1, 0,
    ],
    cool => const [
      0.88, 0, 0, 0, -8, //
      0, 1.0, 0, 0, 2, //
      0, 0, 1.12, 0, 14, //
      0, 0, 0, 1, 0,
    ],
    vivid => _multiply(_contrast(1.15), _saturation(1.6)),
    faded => _multiply(
      _offset(28),
      _multiply(_contrast(0.75), _saturation(0.65)),
    ),
    noir => _multiply(_contrast(1.6), _saturation(0)),
  };
}

/// How a photo is changed in the photo editor's filter mode: a preset, and
/// brightness, contrast and saturation on top, each from -1 to 1, where 0
/// leaves the photo as it is.
@immutable
class PhotoLook {
  final PhotoLookPreset preset;
  final double brightness;
  final double contrast;
  final double saturation;

  const PhotoLook({
    this.preset = PhotoLookPreset.original,
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 0,
  });

  static const neutral = PhotoLook();

  bool get isNeutral => this == neutral;

  PhotoLook copyWith({
    PhotoLookPreset? preset,
    double? brightness,
    double? contrast,
    double? saturation,
  }) => PhotoLook(
    preset: preset ?? this.preset,
    brightness: _slider(brightness ?? this.brightness),
    contrast: _slider(contrast ?? this.contrast),
    saturation: _slider(saturation ?? this.saturation),
  );

  /// Between -1 and 1, and back at 0 when dragged close to the middle, so
  /// the photo can be left as it was without the reset button.
  static double _slider(double value) =>
      value.abs() < 0.05 ? 0 : value.clamp(-1.0, 1.0);

  /// The colour matrix for [ColorFilter.matrix]: the preset first, then
  /// saturation, contrast and brightness. The editor's preview and the
  /// saved photo both use it, so what is shown is what is sent.
  List<double> get matrix => _matrices[this] ??= _computeMatrix();

  static final _matrices = Expando<List<double>>();

  List<double> _computeMatrix() {
    var m = preset.matrix;
    if (saturation != 0) m = _multiply(_saturation(1 + saturation), m);
    if (contrast != 0) m = _multiply(_contrast(1 + contrast * 0.6), m);
    if (brightness != 0) m = _multiply(_offset(brightness * 100), m);
    return m;
  }

  ColorFilter get colorFilter => ColorFilter.matrix(matrix);

  @override
  bool operator ==(Object other) =>
      other is PhotoLook &&
      other.preset == preset &&
      other.brightness == brightness &&
      other.contrast == contrast &&
      other.saturation == saturation;

  @override
  int get hashCode => Object.hash(preset, brightness, contrast, saturation);
}

/// A preset other than [current] and the original, picked by [random]:
/// the editor's dice button.
PhotoLookPreset randomPhotoLookPreset(Random random, PhotoLookPreset current) {
  final choices = PhotoLookPreset.values
      .where((p) => p != PhotoLookPreset.original && p != current)
      .toList();
  return choices[random.nextInt(choices.length)];
}

/// [image] at full size with [look] applied to it, and then [drawOnTop]
/// (the editor's drawing) painted over it without the look, so ink keeps
/// its colour. One pass, so a big photo is copied only once. The caller
/// disposes both images.
Future<ui.Image> paintEditedPhoto(
  ui.Image image, {
  PhotoLook look = PhotoLook.neutral,
  void Function(Canvas canvas, Size size)? drawOnTop,
}) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final paint = Paint();
  if (!look.isNeutral) paint.colorFilter = look.colorFilter;
  canvas.drawImage(image, Offset.zero, paint);
  drawOnTop?.call(
    canvas,
    Size(image.width.toDouble(), image.height.toDouble()),
  );
  return recorder.endRecording().toImage(image.width, image.height);
}

/// A copy of [image] whose longest side is at most [maxSide] pixels, for
/// the presets' small previews. The caller disposes it.
Future<ui.Image> photoLookThumbnail(ui.Image image, {int maxSide = 160}) {
  final scale = min(1.0, maxSide / max(image.width, image.height));
  final width = max(1, (image.width * scale).round());
  final height = max(1, (image.height * scale).round());
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawImageRect(
    image,
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..filterQuality = FilterQuality.medium,
  );
  return recorder.endRecording().toImage(width, height);
}

const _lumR = 0.2126, _lumG = 0.7152, _lumB = 0.0722;

const List<double> _identity = [
  1, 0, 0, 0, 0, //
  0, 1, 0, 0, 0, //
  0, 0, 1, 0, 0, //
  0, 0, 0, 1, 0,
];

/// 0 is grey, 1 unchanged, above 1 more colourful.
List<double> _saturation(double s) {
  final r = _lumR * (1 - s), g = _lumG * (1 - s), b = _lumB * (1 - s);
  return [
    r + s, g, b, 0, 0, //
    r, g + s, b, 0, 0, //
    r, g, b + s, 0, 0, //
    0, 0, 0, 1, 0,
  ];
}

/// Spreads the colours away from mid-grey by [c] (1 is unchanged).
List<double> _contrast(double c) {
  final t = 128 * (1 - c);
  return [
    c, 0, 0, 0, t, //
    0, c, 0, 0, t, //
    0, 0, c, 0, t, //
    0, 0, 0, 1, 0,
  ];
}

/// Adds [o] (0–255 scale) to red, green and blue.
List<double> _offset(double o) => [
  1, 0, 0, 0, o, //
  0, 1, 0, 0, o, //
  0, 0, 1, 0, o, //
  0, 0, 0, 1, 0,
];

/// The matrix that applies [b] first and then [a].
List<double> _multiply(List<double> a, List<double> b) {
  final result = List<double>.filled(20, 0);
  for (var row = 0; row < 4; row++) {
    for (var col = 0; col < 5; col++) {
      var sum = col == 4 ? a[row * 5 + 4] : 0.0;
      for (var k = 0; k < 4; k++) {
        sum += a[row * 5 + k] * b[k * 5 + col];
      }
      result[row * 5 + col] = sum;
    }
  }
  return result;
}

/// The filter mode's controls in the photo editor: the presets, each shown
/// on [thumbnail] (from [photoLookThumbnail]), a dice that picks one, and
/// sliders.
class PhotoLookControls extends StatelessWidget {
  final PhotoLook look;
  final ui.Image? thumbnail;

  /// Null while the photo is being saved: the controls are then locked
  final ValueChanged<PhotoLook>? onChanged;
  final Random? random;

  const PhotoLookControls({
    required this.look,
    required this.thumbnail,
    required this.onChanged,
    this.random,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final onChanged = this.onChanged;
    void change(PhotoLook look) => onChanged?.call(look);
    Widget slider(
      IconData icon,
      String label,
      double value,
      PhotoLook Function(double) changed,
    ) => Row(
      children: [
        const SizedBox(width: 12),
        Tooltip(message: label, child: Icon(icon, size: 20)),
        Expanded(
          child: Slider(
            min: -1,
            max: 1,
            value: value,
            label: label,
            semanticFormatterCallback: (v) => '$label ${(v * 100).round()}',
            onChanged: onChanged == null ? null : (v) => change(changed(v)),
          ),
        ),
      ],
    );
    // Scrolls on short screens, such as a phone turned sideways, so the
    // photo above keeps room
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.45,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 92,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton.filledTonal(
                          visualDensity: VisualDensity.compact,
                          tooltip: l10n.gruppechatLookRandom,
                          icon: const Icon(Icons.casino_outlined),
                          onPressed: () => change(
                            look.copyWith(
                              preset: randomPhotoLookPreset(
                                random ?? Random(),
                                look.preset,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: l10n.reset,
                          icon: const Icon(Icons.restart_alt),
                          onPressed: look.isNeutral
                              ? null
                              : () => change(PhotoLook.neutral),
                        ),
                      ],
                    ),
                  ),
                  for (final preset in PhotoLookPreset.values)
                    _PresetTile(
                      thumbnail: thumbnail,
                      preset: preset,
                      label: preset.label(l10n),
                      selected: look.preset == preset,
                      selectedColor: theme.colorScheme.primary,
                      onTap: () => change(look.copyWith(preset: preset)),
                    ),
                ],
              ),
            ),
            slider(
              Icons.brightness_6_outlined,
              l10n.gruppechatLookBrightness,
              look.brightness,
              (v) => look.copyWith(brightness: v),
            ),
            slider(
              Icons.contrast,
              l10n.gruppechatLookContrast,
              look.contrast,
              (v) => look.copyWith(contrast: v),
            ),
            slider(
              Icons.palette_outlined,
              l10n.gruppechatLookSaturation,
              look.saturation,
              (v) => look.copyWith(saturation: v),
            ),
          ],
        ),
      ),
    );
  }
}

class _PresetTile extends StatelessWidget {
  final ui.Image? thumbnail;
  final PhotoLookPreset preset;
  final String label;
  final bool selected;
  final Color selectedColor;
  final VoidCallback onTap;

  const _PresetTile({
    required this.thumbnail,
    required this.preset,
    required this.label,
    required this.selected,
    required this.selectedColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected ? selectedColor : Colors.transparent,
                    width: 3,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: ColorFiltered(
                    colorFilter: ColorFilter.matrix(preset.matrix),
                    // RawImage disposes what it is given, so it gets its
                    // own handle to the shared small copy
                    child: thumbnail == null
                        // Without a small copy, the look on a warm colour
                        ? const ColoredBox(color: Color(0xFFE09A50))
                        : RawImage(
                            image: thumbnail?.clone(),
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.low,
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall,
                maxLines: 1,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
