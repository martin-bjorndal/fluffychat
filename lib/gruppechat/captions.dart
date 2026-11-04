// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/file_description.dart';
import 'package:matrix/matrix.dart';

extension GruppechatCaptionsExtension on Event {
  /// Whether this is a picture, video, sound or file, whose text is a caption.
  bool get hasCaptionInsteadOfText =>
      type == EventTypes.Message &&
      {
        MessageTypes.Image,
        MessageTypes.Video,
        MessageTypes.Audio,
        MessageTypes.File,
      }.contains(messageType);

  /// The text to put in the input bar when editing this message, given the
  /// message as it is shown now (`getDisplayEvent`). For a picture or a file
  /// that is its caption, not "Alice sent a picture".
  String textToEdit(MatrixLocalizations i18n) => hasCaptionInsteadOfText
      ? fileDescription ?? ''
      : calcLocalizedBodyFallback(
          i18n,
          withSenderNamePrefix: false,
          hideReply: true,
        );
}

extension GruppechatEditCaptionExtension on Event {
  /// Changes the caption of this picture, video, sound or file. The edit
  /// carries the whole file again, as an edit replaces the message's content;
  /// an empty [caption] removes it.
  Future<String?> editCaption(String caption, Timeline timeline) {
    final shown = getDisplayEvent(timeline);
    final content = Map<String, Object?>.of(shown.content)
      ..remove('m.relates_to')
      ..remove('m.new_content')
      ..remove('format')
      ..remove('formatted_body');
    final filename = content.tryGet<String>('filename') ?? shown.body;
    final trimmed = caption.trim();
    content['filename'] = filename;
    content['body'] = trimmed.isEmpty ? filename : trimmed;
    return room.sendEvent(content, editEventId: eventId);
  }
}
