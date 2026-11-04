// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Photos, GIFs, voice messages and files in an encrypted chat, sent the way
// the app sends them (lib/pages/chat/send_file_dialog.dart and
// onVoiceMessageSend in lib/pages/chat/chat.dart) and opened by the other
// person.

@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:fluffychat/gruppechat/gifs.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_file_extension.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:matrix/matrix.dart';
import 'package:mime/mime.dart';

import 'utils/test_server.dart';

Uint8List photo(int width, int height) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(30, 120, 200));
  return img.encodePng(image);
}

/// A GIF with two frames, so it moves.
Uint8List movingGif(int width, int height) {
  final first = img.Image(width: width, height: height);
  img.fill(first, color: img.ColorRgb8(255, 0, 0));
  final second = img.Image(width: width, height: height);
  img.fill(second, color: img.ColorRgb8(0, 0, 255));
  first.addFrame(second);
  return img.encodeGif(first);
}

/// What the recorder writes: Ogg with Opus on Android, MP4 with AAC on iOS
/// and in Safari. Only the start matters for the file type.
Uint8List recording(String container) => Uint8List.fromList([
  ...switch (container) {
    'ogg' => ascii.encode('OggS'),
    'm4a' => [0, 0, 0, 0x20, ...ascii.encode('ftypM4A ')],
    _ => throw ArgumentError(container),
  },
  ...List.filled(4000, 7),
]);

void main() {
  group('Media', skip: skipWithoutTestServer, () {
    late Client alice;
    late Client bob;
    late Room aliceChat;
    late Timeline bobTimeline;

    setUpAll(() async {
      alice = await logIn('alice');
      bob = await logIn('bob');
      final (mine, theirs) = await directChat(alice, bob);
      aliceChat = mine;
      bobTimeline = await theirs.getTimeline();
    });
    tearDownAll(logOutEveryone);

    test('a big photo arrives shrunk, with a thumbnail', () async {
      final bytes = photo(2400, 1800);
      final file = MatrixFile(
        bytes: bytes,
        name: 'photo.png',
        mimeType: 'image/png',
      ).detectFileType;
      expect(file, isA<MatrixImageFile>());
      await aliceChat.sendFileEvent(file, shrinkImageMaxDimension: 1600);

      final event = await arrives(
        bobTimeline,
        'the photo',
        (e) => e.messageType == MessageTypes.Image && e.body == 'photo.png',
      );
      expect(event.isAttachmentEncrypted, isTrue);
      // Shrunk to at most 1600 pixels, as with "compress" on
      final info = event.content.tryGetMap<String, Object?>('info')!;
      expect((info['w'], info['h']), (1600, 1200));
      expect(event.hasThumbnail, isTrue);

      final sent = img.decodeImage(
        (await event.downloadAndDecryptAttachment()).bytes,
      )!;
      expect((sent.width, sent.height), (1600, 1200));
      final thumbnail = img.decodeImage(
        (await event.downloadAndDecryptAttachment(getThumbnail: true)).bytes,
      )!;
      expect(thumbnail.width, lessThan(1600));
      expect(thumbnail.width / thumbnail.height, closeTo(4 / 3, 0.02));
    });

    test('a GIF is sent as it is, so it keeps moving', () async {
      final bytes = movingGif(48, 36);
      await aliceChat.sendFileEvent(GifFile(bytes: bytes, name: 'dans.gif'));

      final event = await arrives(
        bobTimeline,
        'the GIF',
        (e) => e.body == 'dans.gif',
      );
      expect(event.messageType, MessageTypes.Image);
      expect(event.isGif, isTrue);
      final info = event.content.tryGetMap<String, Object?>('info')!;
      expect((info['w'], info['h']), (48, 36));
      // Without a still thumbnail the chat plays the GIF itself
      expect(event.hasThumbnail, isFalse);

      final received = await event.downloadAndDecryptAttachment();
      expect(received.bytes, bytes);
      expect(img.decodeGif(received.bytes)!.numFrames, 2);
    });

    test('a GIF sent in a thread stays in the thread', () async {
      final rootId = await aliceChat.sendTextEvent('Tråd for GIF-er');
      await aliceChat.sendFileEvent(
        GifFile(bytes: movingGif(20, 20), name: 'i-tråden.gif'),
        threadRootEventId: rootId,
        threadLastEventId: rootId,
      );
      final event = await arrives(
        bobTimeline,
        'the GIF in the thread',
        (e) => e.body == 'i-tråden.gif',
      );
      expect(event.relationshipType, RelationshipTypes.thread);
      expect(event.relationshipEventId, rootId);
    });

    for (final (container, from, expectedType) in [
      ('ogg', 'Android', 'audio/ogg'),
      ('m4a', 'iPhone', 'audio/mp4'),
    ]) {
      test('a voice message from $from arrives playable', () async {
        // As onVoiceMessageSend in lib/pages/chat/chat.dart
        final bytes = recording(container);
        var fileName = 'voice_message_1.$container';
        final mimeType = lookupMimeType(fileName, headerBytes: bytes);
        final extension = mimeType == null ? null : extensionFromMime(mimeType);
        if (extension != null) fileName = 'voice_message_2.$extension';
        final file = MatrixAudioFile(
          bytes: bytes,
          name: fileName,
          mimeType: mimeType,
        );
        const duration = 4200;
        const waveform = [10, 200, 600, 1024, 300];
        await aliceChat.sendFileEvent(
          file,
          extraContent: {
            'info': {...file.info, 'duration': duration},
            'org.matrix.msc3245.voice': {},
            'org.matrix.msc1767.audio': {
              'duration': duration,
              'waveform': waveform,
            },
          },
        );

        final event = await arrives(
          bobTimeline,
          'the voice message',
          (e) => e.body == fileName,
        );
        expect(event.messageType, MessageTypes.Audio);
        expect(event.content['org.matrix.msc3245.voice'], isNotNull);
        expect(event.attachmentMimetype, expectedType);
        // What the player reads (lib/pages/chat/events/audio_player.dart)
        expect(
          event.content
              .tryGetMap<String, Object?>('info')
              ?.tryGet<int>('duration'),
          duration,
        );
        expect(
          event.content
              .tryGetMap<String, Object?>('org.matrix.msc1767.audio')
              ?.tryGetList<int>('waveform'),
          waveform,
        );
        final received = await event.downloadAndDecryptAttachment();
        expect(received.bytes, bytes);
        expect(received.mimeType, expectedType);
      });
    }

    test('a file arrives with its name', () async {
      final bytes = Uint8List.fromList(
        utf8.encode('%PDF-1.4\n% Gruppechat test\n%%EOF\n'),
      );
      await aliceChat.sendFileEvent(
        MatrixFile(
          bytes: bytes,
          name: 'handleliste.pdf',
          mimeType: 'application/pdf',
        ).detectFileType,
      );
      final event = await arrives(
        bobTimeline,
        'the file',
        (e) => e.body == 'handleliste.pdf',
      );
      expect(event.messageType, MessageTypes.File);
      final received = await event.downloadAndDecryptAttachment();
      expect(received.bytes, bytes);
      expect(received.name, 'handleliste.pdf');
    });

    test('a deleted photo shows as deleted', () async {
      final eventId = await aliceChat.sendFileEvent(
        MatrixFile(
          bytes: photo(40, 30),
          name: 'uheldig.png',
          mimeType: 'image/png',
        ).detectFileType,
      );
      await arrives(bobTimeline, 'the photo', (e) => e.eventId == eventId);
      await aliceChat.redactEvent(eventId!);
      final deleted = await arrives(
        bobTimeline,
        'the deletion',
        (e) => e.eventId == eventId && e.redacted,
      );
      // The chat shows deleted photos as text (message_content.dart)
      expect(deleted.messageType, isNot(MessageTypes.Image));
      expect(
        await deleted.calcLocalizedBody(const MatrixDefaultLocalizations()),
        startsWith('Removed by'),
      );
    });
  });
}
