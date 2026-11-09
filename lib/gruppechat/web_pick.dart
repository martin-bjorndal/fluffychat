// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// When a pick in the browser is over (the page's side is in
/// `web_files_browser.dart`).
///
/// file_picker took its `<input type="file">` off the page as soon as the
/// picker opened and then only listened for the input's `change` and `cancel`
/// events. Safari on iPhone, in a web app on the home screen too, doesn't
/// always send those for an input that is no longer on the page, so the
/// loading circle after picking a picture or video turned forever. Here the
/// input stays on the page until the pick is over, and the pick also ends
/// when files turn up on the input without an event, or when the page has
/// had its focus back for a long while with nothing picked.
library;

import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';

/// The `accept` attribute for a file input. file_picker gave pictures and
/// videos together as `video/*|image/*`, which browsers don't understand.
String webPickerAccept(FileType type, [List<String>? allowedExtensions]) =>
    switch (type) {
      FileType.any => '',
      FileType.image => 'image/*',
      FileType.video => 'video/*',
      FileType.audio => 'audio/*',
      FileType.media => 'image/*,video/*',
      FileType.custom => [
        for (final extension in allowedExtensions ?? const <String>[])
          '.${extension.replaceFirst(RegExp(r'^\.'), '')}',
      ].join(','),
    };

/// One pick, from opening the picker until there are files or there won't
/// be any. The browser side reports what happens; [result] gives the files,
/// or none when the pick was cancelled.
class WebFilePick {
  WebFilePick({
    required this.selectedCount,
    required this.readFiles,
    this.checkEvery = const Duration(milliseconds: 500),
    this.giveUpAfterFocus = const Duration(minutes: 2),
  }) {
    _checking = Timer.periodic(checkEvery, (_) => _check());
  }

  /// How many files the input holds right now.
  final int Function() selectedCount;

  /// Reads the files the input holds.
  final Future<List<XFile>> Function() readFiles;

  /// How often the input is looked at, in case no event comes.
  final Duration checkEvery;

  /// How long the page may have its focus back with nothing picked before
  /// the pick counts as cancelled. Only a fallback for browsers that send no
  /// cancel event: Safari on iPhone gives the page its focus back while it
  /// still prepares a video, which can take a while for a long one.
  final Duration giveUpAfterFocus;

  final _result = Completer<List<XFile>>();
  late final Timer _checking;
  Timer? _givingUp;
  bool _reading = false;

  Future<List<XFile>> get result => _result.future;

  bool get isOver => _result.isCompleted || _reading;

  /// The input's `change` event.
  void changed() => _check();

  /// The input's `cancel` event: the picker closed without a new choice.
  void cancelled() {
    if (isOver) return;
    if (selectedCount() > 0) return _check();
    _finish(const []);
  }

  /// The page got its focus back, which it also does while a picked video
  /// is still being prepared.
  void focused() {
    if (isOver) return;
    _givingUp?.cancel();
    _givingUp = Timer(giveUpAfterFocus, () {
      if (!isOver && selectedCount() == 0) _finish(const []);
    });
  }

  void _check() {
    if (isOver || selectedCount() == 0) return;
    _reading = true;
    _stopTimers();
    readFiles().then(
      _complete,
      onError: (Object e, StackTrace s) {
        if (!_result.isCompleted) _result.completeError(e, s);
      },
    );
  }

  void _finish(List<XFile> files) {
    _stopTimers();
    _complete(files);
  }

  void _complete(List<XFile> files) {
    if (!_result.isCompleted) _result.complete(files);
  }

  void _stopTimers() {
    _checking.cancel();
    _givingUp?.cancel();
  }
}
