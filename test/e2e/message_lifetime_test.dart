// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Messages that disappear: alice gives her chat with carol a lifetime from
// the chat's details, and what both send after that, a photo too, counts
// down and is then gone for good, from the server and without a trace in
// the chat (lib/gruppechat/message_lifetime.dart and
// deploy/synapse-modules/gruppechat_lifetime.py). What came before stays,
// and so does what comes after she turns it off. The countdown and the
// notification that goes away by itself can only be seen on a phone.

@Timeout(Duration(minutes: 3))
library;

import 'package:collection/collection.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/gruppechat/message_lifetime.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/test_server.dart';

void main() {
  group('Messages that disappear', skip: skipWithoutTestServer, () {
    late Client alice;
    late Client carol;
    late Room aliceChat;
    late Room carolChat;
    late Timeline aliceTimeline;
    late Timeline carolTimeline;
    late GruppechatExpiringMedia aliceMedia;
    late String before;
    late String secret;
    late Event photo;
    // Hours in the app; seconds here, so the test doesn't wait
    const lifetime = Duration(seconds: 20);

    Event? byId(Timeline timeline, String eventId) =>
        timeline.events.firstWhereOrNull((e) => e.eventId == eventId);

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      await AppSettings.init(loadWebConfigFile: false);
      alice = await logIn('alice');
      carol = await logIn('carol');
      (aliceChat, carolChat) = await directChat(alice, carol);
      aliceTimeline = await aliceChat.getTimeline();
      carolTimeline = await carolChat.getTimeline();
      // As the app does for everyone logged in (lib/widgets/matrix.dart)
      aliceMedia = GruppechatExpiringMedia(alice)..start();
    });
    tearDownAll(() async {
      aliceMedia.cancel();
      // Other tests share this chat
      await gruppechatSetMessageLifetime(aliceChat, null);
      await logOutEveryone();
    });

    test('alice turns it on, and what is sent after it counts down', () async {
      before = (await aliceChat.sendTextEvent('Før'))!;
      await arrives(
        carolTimeline,
        'the message before',
        (e) => e.eventId == before,
      );

      expect(gruppechatCanSetMessageLifetime(aliceChat), isTrue);
      await gruppechatSetMessageLifetime(aliceChat, lifetime);
      await eventually(
        'carol sees the lifetime',
        () => gruppechatMessageLifetime(carolChat) == lifetime,
      );

      secret = (await carolChat.sendTextEvent('Hemmelig'))!;
      final bytes = img.encodePng(
        img.fill(
          img.Image(width: 2400, height: 1800),
          color: img.ColorRgb8(200, 60, 90),
        ),
      );
      await aliceChat.sendFileEvent(
        MatrixImageFile(bytes: bytes, name: 'bilde.png', mimeType: 'image/png'),
        shrinkImageMaxDimension: 1600,
      );

      final message = await arrives(
        aliceTimeline,
        "carol's message",
        (e) => e.eventId == secret,
      );
      photo = await arrives(
        carolTimeline,
        "alice's photo",
        (e) => e.messageType == MessageTypes.Image,
      );
      for (final event in [message, photo]) {
        final expiresAt = gruppechatExpiresAt(event)!;
        expect(expiresAt, event.originServerTs.add(lifetime));
        expect(gruppechatIsGone(event), isFalse);
        expect(event.isVisibleInGui, isTrue);
      }
      // The file and its thumbnail
      expect(gruppechatMediaOf(photo), hasLength(2));
      // A notification about it goes away when it does
      expect(
        gruppechatNotificationTimeout(message),
        inInclusiveRange(1, lifetime.inMilliseconds),
      );
      // The message before stays
      expect(gruppechatExpiresAt(byId(carolTimeline, before)!), isNull);
      // Setting it shows no line in the chat
      expect(
        carolTimeline.events.filterByVisibleInGui().map((e) => e.type),
        isNot(contains(gruppechatLifetimeType)),
      );
    });

    test('when the time is up, it is gone without a trace', () async {
      // The app hides it as soon as the time is up
      final message = byId(aliceTimeline, secret)!;
      expect(
        gruppechatIsGone(message, now: message.originServerTs.add(lifetime)),
        isTrue,
      );

      // And the server removes it, for everyone
      for (final (timeline, eventId) in [
        (aliceTimeline, secret),
        (carolTimeline, secret),
        (carolTimeline, photo.eventId),
      ]) {
        await eventually(
          '$eventId is removed for ${timeline.room.client.userID}',
          () => byId(timeline, eventId)?.redacted ?? true,
        );
        final event = byId(timeline, eventId);
        if (event != null) {
          expect(gruppechatIsGone(event), isTrue);
          expect(event.isVisibleInGui, isFalse);
        }
        expect(
          timeline.events.filterByVisibleInGui().map((e) => e.eventId),
          isNot(contains(eventId)),
        );
      }
      final fromServer = await carol.getOneRoomEvent(carolChat.id, secret);
      expect(fromServer.content.keys, isNot(contains('ciphertext')));

      // The photo's files are deleted too
      for (final mxc in gruppechatMediaOf(photo)) {
        final uri = Uri.parse(mxc);
        await expectLater(
          carol.getContentAuthed(uri.host, uri.pathSegments.single),
          throwsA(
            isA<MatrixException>().having(
              (e) => e.error,
              'error',
              MatrixError.M_NOT_FOUND,
            ),
          ),
        );
      }

      // What came before is still there
      final kept = byId(carolTimeline, before)!;
      expect(kept.redacted, isFalse);
      expect(kept.isVisibleInGui, isTrue);
    });

    test('turned off, new messages stay as usual', () async {
      await gruppechatSetMessageLifetime(aliceChat, null);
      await eventually(
        'carol sees it is off',
        () => gruppechatMessageLifetime(carolChat) == null,
      );
      final after = (await carolChat.sendTextEvent('Etter'))!;
      final event = await arrives(
        aliceTimeline,
        'the message after',
        (e) => e.eventId == after,
      );
      expect(gruppechatExpiresAt(event), isNull);
      await Future<void>.delayed(lifetime + const Duration(seconds: 3));
      expect(byId(aliceTimeline, after)?.redacted, isFalse);
      expect(byId(carolTimeline, after)?.redacted, isFalse);
    });
  });
}
