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

import 'package:cross_file/cross_file.dart';
import 'package:fluffychat/gruppechat/captions.dart';
import 'package:fluffychat/gruppechat/gifs.dart';
import 'package:fluffychat/gruppechat/pending_attachments.dart';
import 'package:fluffychat/gruppechat/stickers.dart';
import 'package:fluffychat/gruppechat/video_opening.dart';
import 'package:fluffychat/gruppechat/video_source.dart';
import 'package:fluffychat/gruppechat/web_pick.dart';
import 'package:fluffychat/utils/file_description.dart';
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

    test(
      'a photo and a video picked in the web app on an iPhone arrive',
      () async {
        // Safari gives the page its focus back, prepares the video and puts
        // both on the file input without a change event
        // (lib/gruppechat/web_pick.dart, as the web app's picker uses it)
        final picked = <XFile>[];
        final pick = WebFilePick(
          selectedCount: () => picked.length,
          readFiles: () async => List.of(picked),
          checkEvery: const Duration(milliseconds: 50),
        );
        pick.focused();
        await Future<void>.delayed(const Duration(seconds: 1));
        final jpeg = photo(2000, 1500);
        picked
          ..add(
            // As the picker reads Safari's File (webPickedFile)
            webPickedFile(
              jpeg,
              name: 'IMG_0001.jpeg',
              type: 'image/jpeg',
              size: jpeg.length,
              lastModified: 1762650000000,
            ),
          )
          ..add(
            webPickedFile(
              Uint8List.fromList([
                0, 0, 0, 0x14, ...ascii.encode('ftypqt  '), //
                ...List.filled(5000, 3),
              ]),
              name: 'IMG_0002.MOV',
              type: 'video/quicktime',
              size: 5012,
            ),
          );
        final files = await pick.result.timeout(const Duration(seconds: 10));
        expect(files.map((f) => f.name), ['IMG_0001.jpeg', 'IMG_0002.MOV']);

        // Sent the way the send dialog does in the browser
        for (final xfile in files) {
          await aliceChat.sendFileEvent(
            fileToSend(await xfile.readAsBytes(), xfile.name, xfile.mimeType),
            shrinkImageMaxDimension: 1600,
          );
        }

        final image = await arrives(
          bobTimeline,
          'the photo from the web app',
          (e) => e.body == 'IMG_0001.jpeg',
        );
        expect(image.messageType, MessageTypes.Image);
        final sent = img.decodeImage(
          (await image.downloadAndDecryptAttachment()).bytes,
        )!;
        expect((sent.width, sent.height), (1600, 1200));

        final video = await arrives(
          bobTimeline,
          'the video from the web app',
          (e) => e.body == 'IMG_0002.MOV',
        );
        expect(video.messageType, MessageTypes.Video);
        expect(video.attachmentMimetype, 'video/quicktime');
        final received = await video.downloadAndDecryptAttachment();
        expect(received.bytes, await files.last.readAsBytes());
      },
    );

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

    test('a sticker shows while it is being sent, and arrives', () async {
      final bytes = photo(64, 64);
      final url = await alice.uploadContent(
        bytes,
        filename: 'katt.png',
        contentType: 'image/png',
      );
      final sticker = ImagePackImageContent(
        url: url,
        body: 'katt',
        info: {'w': 64, 'h': 64, 'mimetype': 'image/png'},
      );

      // The chat shows the sticker at once, before the server has it
      final onTheWay = alice.onTimelineEvent.stream.firstWhere(
        (e) =>
            e.roomId == aliceChat.id &&
            e.type == EventTypes.Sticker &&
            !e.status.isSent,
      );
      final sending = sendSticker(aliceChat, sticker);
      final echo = await onTheWay;
      final shown = await echo.downloadableAttachment
          .downloadAndDecryptAttachment(getThumbnail: echo.hasThumbnail);
      expect(shown.bytes, bytes);
      expect(await sending, isNotNull);

      final event = await arrives(
        bobTimeline,
        'the sticker',
        (e) => e.type == EventTypes.Sticker && e.body == 'katt',
      );
      final received = await event.downloadableAttachment
          .downloadAndDecryptAttachment(getThumbnail: event.hasThumbnail);
      expect(received.bytes, bytes);
    });

    test('a forwarded photo shows while it is being sent', () async {
      final bytes = photo(40, 30);
      await aliceChat.sendFileEvent(
        MatrixImageFile(bytes: bytes, name: 'videre.png'),
      );
      final original = await arrives(
        bobTimeline,
        'the photo to forward',
        (e) => e.body == 'videre.png',
      );

      final onTheWay = bob.onTimelineEvent.stream.firstWhere(
        (e) =>
            e.roomId == bobTimeline.room.id &&
            e.body == 'videre.png' &&
            !e.status.isSent,
      );
      // As the chat forwards a message: its content, sent again
      final sending = bobTimeline.room.sendEvent(original.content.copy());
      final echo = await onTheWay;
      final shown = await echo.downloadableAttachment
          .downloadAndDecryptAttachment(getThumbnail: echo.hasThumbnail);
      expect(shown.bytes, bytes);
      // And the forward still goes out
      expect(await sending, isNotNull);
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

    test("a photo's caption can be changed, and the photo stays", () async {
      final eventId = await aliceChat.sendFileEvent(
        MatrixFile(
          bytes: photo(40, 30),
          name: 'ferie.png',
          mimeType: 'image/png',
        ).detectFileType,
        // As the send dialog adds a caption
        extraContent: {'body': 'Fra stranda'},
      );
      final aliceTimeline = await aliceChat.getTimeline();
      Event mine() =>
          aliceTimeline.events.firstWhere((e) => e.eventId == eventId);
      await arrives(aliceTimeline, 'the photo', (e) => e.eventId == eventId);
      const i18n = MatrixDefaultLocalizations();
      Future<Event> bobSees(String what, bool Function(Event shown) test) =>
          valueOf(what, () {
            final shown = bobTimeline.events
                .where((e) => e.eventId == eventId)
                .singleOrNull
                ?.getDisplayEvent(bobTimeline);
            return shown != null && test(shown) ? shown : null;
          });

      // Editing starts from the caption, not "alice sent a picture"
      expect(
        mine().getDisplayEvent(aliceTimeline).textToEdit(i18n),
        'Fra stranda',
      );
      await mine().editCaption('Fra stranda i Lofoten', aliceTimeline);
      final edited = await bobSees(
        'the new caption',
        (shown) => shown.fileDescription == 'Fra stranda i Lofoten',
      );
      expect(edited.messageType, MessageTypes.Image);
      final received = await edited.downloadAndDecryptAttachment();
      expect(img.decodeImage(received.bytes), isNotNull);

      // The next edit starts from the new caption, and an empty one removes it
      await valueOf(
        'alice sees her edit',
        () =>
            mine().getDisplayEvent(aliceTimeline).textToEdit(i18n) ==
                'Fra stranda i Lofoten'
            ? true
            : null,
      );
      await mine().editCaption('', aliceTimeline);
      final plain = await bobSees(
        'the photo without a caption',
        (shown) =>
            shown.eventId != edited.eventId && shown.fileDescription == null,
      );
      expect(plain.messageType, MessageTypes.Image);
      expect(plain.body, 'ferie.png');
      await valueOf(
        'alice sees the photo without a caption',
        () => mine().getDisplayEvent(aliceTimeline).textToEdit(i18n) == ''
            ? true
            : null,
      );
    });

    test('a video closed while it loads stays closed and silent', () async {
      // Big enough to arrive in many pieces, like on a slow connection
      final bytes = Uint8List.fromList(
        List.generate(3 * 1024 * 1024, (i) => (i * 31) % 251),
      );
      await aliceChat.sendFileEvent(
        MatrixVideoFile(
          bytes: bytes,
          name: 'tur.mp4',
          mimeType: 'video/mp4',
          width: 640,
          height: 360,
        ),
      );
      final event = await arrives(
        bobTimeline,
        'the video',
        (e) => e.body == 'tur.mp4',
      );
      expect(event.messageType, MessageTypes.Video);

      // bob opens the video and closes it as soon as it starts loading
      final opening = VideoOpening();
      var progressAfterClosing = 0;
      final file = await opening.download(
        event,
        onProgress: (_) {
          if (opening.isClosed) {
            progressAfterClosing++;
          } else {
            opening.close();
          }
        },
      );
      expect(opening.isClosed, isTrue);
      // The closed viewer hears nothing more, and nothing gets played
      expect(progressAfterClosing, 0);
      expect(file, isNull);
      var disposed = false;
      final player = await opening.keep('player', (_) async => disposed = true);
      expect(player, isNull);
      expect(disposed, isTrue);

      // Opened again and left open, it loads and plays
      final again = VideoOpening();
      final progress = <double?>[];
      final played = await again.download(event, onProgress: progress.add);
      expect(played?.bytes, bytes);
      expect(progress, isNotEmpty);
      expect(
        await again.keep('player', (_) async => fail('disposed')),
        'player',
      );
    });

    test(
      'videos with an odd type from other apps reach the browser as MP4',
      () async {
        // An iPhone video that another app sent without a proper type, and
        // an ordinary MP4. Safari refuses a video whose type it doesn't know.
        final quickTime = Uint8List.fromList([
          0, 0, 0, 0x14, ...ascii.encode('ftypqt  '), //
          ...List.filled(5000, 3),
        ]);
        final mp4 = Uint8List.fromList([
          0, 0, 0, 0x18, ...ascii.encode('ftypmp42'), //
          ...List.filled(5000, 4),
        ]);
        for (final (name, bytes, type) in [
          ('IMG_0003.MOV', quickTime, 'application/octet-stream'),
          ('klipp.mp4', mp4, 'video/x-m4v'),
        ]) {
          await aliceChat.sendFileEvent(
            MatrixVideoFile(bytes: bytes, name: name, mimeType: type),
          );
        }

        // bob opens each in the web app's video viewer, which tells the
        // browser the type the bytes have (outside the browser the source is
        // a data: URL, so the type can be read back)
        final played = <String, String?>{};
        for (final (name, bytes) in [
          ('IMG_0003.MOV', quickTime),
          ('klipp.mp4', mp4),
        ]) {
          final event = await arrives(bobTimeline, name, (e) => e.body == name);
          expect(event.messageType, MessageTypes.Video);
          final file = await VideoOpening().download(event);
          expect(file!.bytes, bytes);
          final source = WebVideoSource(file);
          played[name] = source.uri.data?.mimeType;
          source.release();
          expect(source.isReleased, isTrue);
        }
        expect(played, {'IMG_0003.MOV': 'video/mp4', 'klipp.mp4': 'video/mp4'});
      },
    );

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
