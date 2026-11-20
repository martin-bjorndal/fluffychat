// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Several photos picked at once go as a series, with one message, and
// show as one stack with the first photo on top.
library;

import 'dart:typed_data';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/gruppechat/captions.dart';
import 'package:fluffychat/gruppechat/file_series.dart';
import 'package:fluffychat/gruppechat/photo_stacks.dart';
import 'package:fluffychat/utils/file_description.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_file_extension.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/test_server.dart';

Uint8List photo(int width, int height) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(200, 120, 30));
  return img.encodePng(image);
}

void main() {
  group('File series', skip: skipWithoutTestServer, () {
    late Client alice;
    late Client bob;
    late Room aliceChat;
    late Timeline bobTimeline;

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      await AppSettings.init(loadWebConfigFile: false);
      alice = await logIn('alice');
      bob = await logIn('bob');
      final (mine, theirs) = await directChat(alice, bob);
      aliceChat = mine;
      bobTimeline = await theirs.getTimeline();
    });
    tearDownAll(logOutEveryone);

    /// Sends [names] the way the send dialog does when they are picked
    /// together with [message], as a reply to [inReplyTo] if given.
    Future<List<String?>> sendTogether(
      List<String> names,
      String message, {
      Event? inReplyTo,
    }) async {
      final contents = fileSeriesContents(
        alice,
        caption: message,
        count: names.length,
      );
      return [
        for (final (i, name) in names.indexed)
          await aliceChat.sendFileEvent(
            MatrixFile(
              bytes: photo(40, 30),
              name: name,
              mimeType: 'image/png',
            ).detectFileType,
            extraContent: contents[i],
            inReplyTo: fileReplyTarget(inReplyTo, i),
          ),
      ];
    }

    Future<Event> bobSees(String name) => arrives(
      bobTimeline,
      name,
      (e) =>
          e.messageType == MessageTypes.Image &&
          e.content.tryGet<String>('filename') == name,
    );

    test('three photos go as one series with the message once', () async {
      // Martin's photos from a walk, with a few words
      final ids = await sendTogether([
        'tur1.png',
        'tur2.png',
        'tur3.png',
      ], '  Frå turen i dag  ');
      final photos = [
        await bobSees('tur1.png'),
        await bobSees('tur2.png'),
        await bobSees('tur3.png'),
      ];

      final series = photos.map((e) => e.fileSeries).toList();
      expect(series.every((s) => s != null), isTrue);
      expect(series.map((s) => s!.id).toSet(), hasLength(1));
      expect(series.map((s) => s!.index), [0, 1, 2]);
      expect(series.map((s) => s!.count), [3, 3, 3]);
      // The message shows once, with the first photo
      expect(photos.map((e) => e.fileDescription), [
        'Frå turen i dag',
        null,
        null,
      ]);

      // Changing the message keeps the photo in its series
      final aliceTimeline = await aliceChat.getTimeline();
      final captioned = await arrives(
        aliceTimeline,
        'the first photo',
        (e) => e.eventId == ids.first,
      );
      await captioned.editCaption('Frå turen til Preikestolen', aliceTimeline);
      final edited = await valueOf('the new message', () {
        final shown = bobTimeline.events
            .where((e) => e.eventId == ids.first)
            .singleOrNull
            ?.getDisplayEvent(bobTimeline);
        return shown?.fileDescription == 'Frå turen til Preikestolen'
            ? shown
            : null;
      });
      expect(edited.fileSeries, series.first);

      // Bob forwards the second photo to Carol: there it stands on its own
      final carol = await logIn('carol');
      final (bobToCarol, carolChat) = await directChat(bob, carol);
      await bobToCarol.sendEvent(photos[1].forwardedContent);
      final forwarded = await arrives(
        await carolChat.getTimeline(),
        'the forwarded photo',
        (e) =>
            e.messageType == MessageTypes.Image &&
            e.content.tryGet<String>('filename') == 'tur2.png',
      );
      expect(forwarded.fileSeries, isNull);
    });

    /// Bob's chat as the list shows it: the messages, newest first, and
    /// the photos of each stack.
    (List<Event>, PhotoStacks) bobsList() {
      final stacks = <String, List<Event>>{};
      final shown = stackPhotoSeries(
        bobTimeline.events.filterByVisibleInGui(),
        stacks,
        timeline: bobTimeline,
      );
      return (shown, stacks);
    }

    List<String?> names(Iterable<Event> events) =>
        events.map((e) => e.content.tryGet<String>('filename')).toList();

    test('Bob sees a series as one stack, the first photo on top', () async {
      // Martin sends four photos from a trip, with a few words
      final ids = await sendTogether([
        'stabel1.png',
        'stabel2.png',
        'stabel3.png',
        'stabel4.png',
      ], 'Fire frå hytta');
      await bobSees('stabel4.png');

      var (shown, stacks) = bobsList();
      // One item for the four photos: the first, which has the message
      expect(names(shown.take(1)), ['stabel1.png']);
      expect(shown.first.fileDescription, 'Fire frå hytta');
      expect(names(GruppechatPhotoStacks.photosOf(stacks, shown.first)), [
        'stabel1.png',
        'stabel2.png',
        'stabel3.png',
        'stabel4.png',
      ]);
      // A jump to the third photo (a reply to it, say) lands on the stack
      expect(
        stackedIndexOf(
          bobTimeline.events.filterByVisibleInGui(),
          ids[2]!,
          timeline: bobTimeline,
        ),
        0,
      );
      // and Bob's read marker on the last photo shows on the stack
      expect(isInItem(stacks, shown.first, ids[3]), isTrue);
      expect(isInItem(stacks, shown[1], ids[3]), isFalse);

      // Alice changes the message: the changed photo still tops the stack
      final aliceTimeline = await aliceChat.getTimeline();
      final first = await arrives(
        aliceTimeline,
        'the first photo',
        (e) => e.eventId == ids.first,
      );
      await first.editCaption('Fire frå hytta i går', aliceTimeline);
      final shownFirst = await valueOf('the changed message', () {
        final top = bobsList().$1.first.getDisplayEvent(bobTimeline);
        return top.fileDescription == 'Fire frå hytta i går' ? top : null;
      });
      expect(
        GruppechatPhotoStacks.photosOf(bobsList().$2, shownFirst),
        hasLength(4),
      );

      // Alice deletes the first photo: the second comes on top
      await aliceChat.redactEvent(ids.first!);
      await eventually(
        'bob sees the first photo deleted',
        () =>
            bobTimeline.events.any((e) => e.eventId == ids.first && e.redacted),
      );
      (shown, stacks) = bobsList();
      final top = shown.firstWhere((e) => e.eventId == ids[1]);
      expect(names(GruppechatPhotoStacks.photosOf(stacks, top)), [
        'stabel2.png',
        'stabel3.png',
        'stabel4.png',
      ]);
      expect(
        shown.any((e) => e.eventId == ids[2] || e.eventId == ids[3]),
        isFalse,
      );
    });

    test('a message in between splits a series in two stacks', () async {
      // Bob writes while Alice's photos are still going out
      final contents = fileSeriesContents(alice, caption: '', count: 3);
      Future<String?> send(int i) => aliceChat.sendFileEvent(
        MatrixFile(
          bytes: photo(40, 30),
          name: 'delt${i + 1}.png',
          mimeType: 'image/png',
        ).detectFileType,
        extraContent: contents[i],
      );
      await send(0);
      await bobSees('delt1.png');
      await bobTimeline.room.sendTextEvent('Så fint!');
      await arrives(bobTimeline, 'what bob wrote', (e) => e.body == 'Så fint!');
      await send(1);
      await send(2);
      await bobSees('delt3.png');

      final (shown, stacks) = bobsList();
      final newest = shown.take(3).toList();
      expect(names(newest), ['delt2.png', null, 'delt1.png']);
      expect(newest[1].body, 'Så fint!');
      expect(names(GruppechatPhotoStacks.photosOf(stacks, newest[0])), [
        'delt2.png',
        'delt3.png',
      ]);
      expect(GruppechatPhotoStacks.photosOf(stacks, newest[2]), isEmpty);
    });

    test('a series without a message has no caption', () async {
      await sendTogether(['utan1.png', 'utan2.png'], ' ');
      final first = await bobSees('utan1.png');
      final second = await bobSees('utan2.png');
      expect(first.fileDescription, isNull);
      expect(second.fileDescription, isNull);
      expect(second.fileSeries?.id, first.fileSeries?.id);
      expect(second.fileSeries?.index, 1);
    });

    test('one photo with a message is not a series', () async {
      await sendTogether(['aleine.png'], 'Berre denne');
      final one = await bobSees('aleine.png');
      expect(one.fileDescription, 'Berre denne');
      expect(one.fileSeries, isNull);
      expect(one.content.containsKey(gruppechatSeriesKey), isFalse);
    });

    test('Alice answers Bob with two photos: the first is the reply', () async {
      final question = await bob
          .getRoomById(aliceChat.id)!
          .sendTextEvent('Korleis var utsikta?');
      final bobsMessage = await arrives(
        await aliceChat.getTimeline(),
        "Bob's question",
        (e) => e.eventId == question,
      );

      await sendTogether(
        ['svar1.png', 'svar2.png'],
        'Sjå sjølv',
        inReplyTo: bobsMessage,
      );
      final first = await bobSees('svar1.png');
      final second = await bobSees('svar2.png');

      expect(first.inReplyToEventId(includingFallback: false), question);
      expect(second.inReplyToEventId(includingFallback: false), isNull);
      // The quote of Bob's message doesn't show up as the photo's message
      expect(first.fileDescription, 'Sjå sjølv');
      expect(second.fileDescription, isNull);
      expect(second.fileSeries?.id, first.fileSeries?.id);
      // The two photos show as one stack, the reply on top
      final (shown, stacks) = bobsList();
      expect(names(shown.take(1)), ['svar1.png']);
      expect(names(GruppechatPhotoStacks.photosOf(stacks, shown.first)), [
        'svar1.png',
        'svar2.png',
      ]);
    });

    test('one photo as a reply, without a message, has no caption', () async {
      final question = await bob
          .getRoomById(aliceChat.id)!
          .sendTextEvent('Har du eit bilete?');
      final bobsMessage = await arrives(
        await aliceChat.getTimeline(),
        "Bob's question",
        (e) => e.eventId == question,
      );
      await sendTogether(['berre.png'], '', inReplyTo: bobsMessage);
      final photo = await bobSees('berre.png');
      expect(photo.inReplyToEventId(includingFallback: false), question);
      expect(photo.fileDescription, isNull);
    });
  });
}
