// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Two people writing to each other in an encrypted direct chat: messages,
// edits, replies, reactions, typing, emojis, locations, polls, profiles and
// deleting.

@Timeout(Duration(minutes: 3))
library;

import 'dart:typed_data';

import 'package:fluffychat/gruppechat/emoji.dart';
import 'package:fluffychat/gruppechat/message_actions.dart';
import 'package:fluffychat/utils/client_download_content_extension.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:matrix/matrix.dart';

import 'utils/test_server.dart';

/// What the app shows for [event] in the chat list and notifications.
Future<String> shownText(Event event) =>
    event.calcLocalizedBody(const MatrixDefaultLocalizations());

/// Shown as "Removed by …", never as a message that couldn't be decrypted.
Future<void> expectShownAsDeleted(Event event) async {
  expect(event.redacted, isTrue, reason: 'the message is deleted');
  expect(event.messageType, isNot(MessageTypes.BadEncrypted));
  final text = await shownText(event);
  expect(text, startsWith('Removed by'));
  expect(text, isNot(contains('decrypt')));
}

void main() {
  group('Direct chats', skip: skipWithoutTestServer, () {
    late Client alice;
    late Client bob;
    late Room aliceChat;
    late Room bobChat;
    late Timeline aliceTimeline;
    late Timeline bobTimeline;

    setUpAll(() async {
      alice = await logIn('alice');
      bob = await logIn('bob');
      (aliceChat, bobChat) = await directChat(alice, bob);
      aliceTimeline = await aliceChat.getTimeline();
      bobTimeline = await bobChat.getTimeline();
    });
    tearDownAll(logOutEveryone);

    test('are encrypted, and both people may do anything in them', () {
      expect(aliceChat.encrypted, isTrue);
      expect(bobChat.encrypted, isTrue);
      expect(aliceChat.directChatMatrixID, bob.userID);
      expect(bobChat.directChatMatrixID, alice.userID);
      expect(bobChat.getPowerLevelByUserId(alice.userID!), 100);
      expect(bobChat.getPowerLevelByUserId(bob.userID!), 100);
    });

    test('a message arrives decrypted', () async {
      await aliceChat.sendTextEvent('Hei Bob!');
      final message = await arrives(
        bobTimeline,
        'the message',
        (e) => e.body == 'Hei Bob!',
      );
      expect(message.type, EventTypes.Message);
      expect(message.senderId, alice.userID);
      expect(await shownText(message), 'Hei Bob!');
    });

    test('an edit replaces the text for the reader', () async {
      final eventId = await aliceChat.sendTextEvent('Første utkast');
      await arrives(bobTimeline, 'the draft', (e) => e.eventId == eventId);
      await aliceChat.sendTextEvent('Endelig tekst', editEventId: eventId);
      await eventually(
        'bob sees the edit',
        () =>
            bobTimeline.events
                .firstWhere((e) => e.eventId == eventId)
                .getDisplayEvent(bobTimeline)
                .body ==
            'Endelig tekst',
      );
    });

    test('a reply points at the message it answers', () async {
      final question = await aliceChat.sendTextEvent('Pizza i kveld?');
      final received = await arrives(
        bobTimeline,
        'the question',
        (e) => e.eventId == question,
      );
      await bobChat.sendTextEvent('Ja!', inReplyTo: received);
      final reply = await arrives(
        aliceTimeline,
        'the reply',
        (e) => e.inReplyToEventId() == question,
      );
      expect(reply.inReplyToEventId(), question);
      expect(
        (await reply.getReplyEvent(aliceTimeline))?.body,
        'Pizza i kveld?',
      );
    });

    test('reactions are collected under the message', () async {
      final eventId = await aliceChat.sendTextEvent('Hvem blir med?');
      await arrives(bobTimeline, 'the question', (e) => e.eventId == eventId);
      await bobChat.sendReaction(eventId!, '👍');
      final message = await arrives(
        aliceTimeline,
        'the question',
        (e) => e.eventId == eventId,
      );
      await eventually(
        'alice sees the reaction',
        () => message
            .aggregatedEvents(aliceTimeline, RelationshipTypes.reaction)
            .any(
              (r) =>
                  r.senderId == bob.userID &&
                  r.content
                          .tryGetMap<String, Object?>('m.relates_to')
                          ?.tryGet<String>('key') ==
                      '👍',
            ),
      );
    });

    test('typing shows for the other person', () async {
      await bobChat.setTyping(true, timeout: 30000);
      await eventually(
        'alice sees bob typing',
        () => aliceChat.typingUsers.any((u) => u.id == bob.userID),
      );
      await bobChat.setTyping(false);
      await eventually(
        'alice sees bob stop',
        () => !aliceChat.typingUsers.any((u) => u.id == bob.userID),
      );
    });

    test('a single emoji is shown big, without a bubble', () async {
      await aliceChat.sendTextEvent('🎉');
      await aliceChat.sendTextEvent('🎉🎉');
      await aliceChat.sendTextEvent('Gratulerer 🎉');
      final single = await arrives(
        bobTimeline,
        'the emoji',
        (e) => e.body == '🎉',
      );
      final double = await arrives(
        bobTimeline,
        'two emojis',
        (e) => e.body == '🎉🎉',
      );
      final mixed = await arrives(
        bobTimeline,
        'the text',
        (e) => e.body == 'Gratulerer 🎉',
      );
      expect(single.isSingleEmojiMessage, isTrue);
      expect(double.isSingleEmojiMessage, isFalse);
      expect(mixed.isSingleEmojiMessage, isFalse);

      // A reply keeps its bubble, which holds the quote
      await bobChat.sendTextEvent('👍', inReplyTo: single);
      final reply = await arrives(
        aliceTimeline,
        'the emoji reply',
        (e) => e.body.endsWith('👍') && e.inReplyToEventId() != null,
      );
      expect(
        reply.isSingleEmojiMessage &&
            reply.inReplyToEventId(includingFallback: false) == null,
        isFalse,
      );
    });

    test('double tapping edits only your own sent text', () async {
      final own = await aliceChat.sendTextEvent('Min melding');
      await bobChat.sendTextEvent('Bobs melding');
      final mine = await arrives(
        aliceTimeline,
        'her message',
        (e) => e.eventId == own && e.status.isSent,
      );
      final theirs = await arrives(
        aliceTimeline,
        'bob\'s message',
        (e) => e.body == 'Bobs melding',
      );
      expect(mine.editsOnDoubleTap, isTrue);
      expect(theirs.editsOnDoubleTap, isFalse);
    });

    test('a location arrives as coordinates', () async {
      await aliceChat.sendLocation('Her er jeg', 'geo:59.9139,10.7522');
      final location = await arrives(
        bobTimeline,
        'the location',
        (e) => e.messageType == MessageTypes.Location,
      );
      // How the chat reads it before drawing the map
      final latLong = Uri.parse(
        location.content['geo_uri'] as String,
      ).path.split(';').first.split(',').map(double.parse).toList();
      expect(latLong, [59.9139, 10.7522]);
    });

    test('a poll collects votes and can be ended', () async {
      // As lib/pages/chat/start_poll_bottom_sheet.dart
      final pollId = await aliceChat.startPoll(
        question: 'Når møtes vi?',
        answers: [
          PollAnswer(id: '1', mText: 'Fredag'),
          PollAnswer(id: '2', mText: 'Lørdag'),
        ],
        kind: PollKind.disclosed,
      );
      Event bobsPoll() =>
          bobTimeline.events.firstWhere((e) => e.eventId == pollId);
      final poll = await arrives(
        bobTimeline,
        'the poll',
        (e) => e.eventId == pollId,
      );
      expect(
        poll.parsedPollEventContent.pollStartContent.question.mText,
        'Når møtes vi?',
      );
      await poll.answerPoll(['2']);
      await arrives(aliceTimeline, 'the poll', (e) => e.eventId == pollId);
      await eventually(
        'alice sees bob\'s vote',
        () =>
            aliceTimeline.events
                .firstWhere((e) => e.eventId == pollId)
                .getPollResponses(aliceTimeline)[bob.userID]
                ?.contains('2') ??
            false,
      );
      await aliceTimeline.events
          .firstWhere((e) => e.eventId == pollId)
          .endPoll();
      await eventually(
        'bob sees the poll ended',
        () => bobsPoll().getPollHasBeenEnded(bobTimeline),
      );
    });

    test('a new name and profile picture show for the other person', () async {
      // As the settings page does
      await alice.setProfileField(alice.userID!, 'displayname', {
        'displayname': 'Alice A.',
      });
      final picture = Uint8List.fromList(
        img.encodePng(img.Image(width: 64, height: 64)),
      );
      await alice.setAvatar(MatrixFile(bytes: picture, name: 'meg.png'));
      try {
        await eventually(
          'bob sees the new name on the chat',
          () => bobChat.getLocalizedDisplayname() == 'Alice A.',
        );
        final url = await valueOf(
          'bob sees the new picture',
          () => bobChat
              .unsafeGetUserFromMemoryOrFallback(alice.userID!)
              .avatarUrl,
        );
        final downloaded = await bob.downloadMxcCached(url);
        expect(downloaded, picture);
      } finally {
        await alice.setProfileField(alice.userID!, 'displayname', {
          'displayname': 'alice',
        });
        await alice.setAvatar(null);
      }
    });
  });

  group('Deleted messages', skip: skipWithoutTestServer, () {
    late Client alice;
    late Client bob;
    late Room aliceChat;
    late Room bobChat;
    late Timeline bobTimeline;

    setUpAll(() async {
      alice = await logIn('alice');
      bob = await logIn('bob');
      (aliceChat, bobChat) = await directChat(alice, bob);
      bobTimeline = await bobChat.getTimeline();
    });
    tearDownAll(logOutEveryone);

    test('show as deleted for someone who had read them', () async {
      final eventId = await aliceChat.sendTextEvent('Oops, feil chat');
      final message = await arrives(
        bobTimeline,
        'the message',
        (e) => e.eventId == eventId,
      );
      expect(message.body, 'Oops, feil chat');
      await aliceChat.redactEvent(eventId!);
      final deleted = await arrives(
        bobTimeline,
        'the deletion',
        (e) => e.eventId == eventId && e.redacted,
      );
      await expectShownAsDeleted(deleted);
      await eventually(
        'the chat list shows the deletion',
        () => bobChat.lastEvent?.eventId == eventId,
      );
      await expectShownAsDeleted(bobChat.lastEvent!);
    });

    test('show as deleted on a device that logs in later', () async {
      final eventId = await aliceChat.sendTextEvent('Hemmelig');
      await arrives(bobTimeline, 'the message', (e) => e.eventId == eventId);
      await aliceChat.redactEvent(eventId!);
      await arrives(
        bobTimeline,
        'the deletion',
        (e) => e.eventId == eventId && e.redacted,
      );

      final bobsNewPhone = await logIn('bob');
      final chat = await joined(bobsNewPhone, bobChat.id);
      final timeline = await chat.getTimeline();
      final deleted = await inHistory(
        timeline,
        'the deleted message',
        (e) => e.eventId == eventId,
      );
      await expectShownAsDeleted(deleted);
      await expectShownAsDeleted(chat.lastEvent!);
    });

    test('show as deleted when quoted in a reply', () async {
      final eventId = await aliceChat.sendTextEvent('Dette angrer jeg på');
      final original = await arrives(
        bobTimeline,
        'the message',
        (e) => e.eventId == eventId,
      );
      final replyId = await bobChat.sendTextEvent('Hæ?', inReplyTo: original);
      await aliceChat.redactEvent(eventId!);
      await arrives(
        bobTimeline,
        'the deletion',
        (e) => e.eventId == eventId && e.redacted,
      );

      // A device that never saw the message fetches the quote from the server
      final bobsNewPhone = await logIn('bob');
      final chat = await joined(bobsNewPhone, bobChat.id);
      final timeline = await chat.getTimeline();
      final reply = await arrives(
        timeline,
        'the reply',
        (e) => e.eventId == replyId,
      );
      final quoted = await reply.getReplyEvent(timeline);
      expect(quoted, isNotNull);
      await expectShownAsDeleted(quoted!);
    });

    test('an edited message shows as deleted, not as its edit', () async {
      final eventId = await aliceChat.sendTextEvent('Første versjon');
      await arrives(bobTimeline, 'the message', (e) => e.eventId == eventId);
      await aliceChat.sendTextEvent('Rettet versjon', editEventId: eventId);
      await eventually(
        'bob sees the edit',
        () =>
            bobTimeline.events
                .firstWhere((e) => e.eventId == eventId)
                .getDisplayEvent(bobTimeline)
                .body ==
            'Rettet versjon',
      );
      // The chat's delete action deletes the message, not its edits
      await aliceChat.redactEvent(eventId!);
      final deleted = await arrives(
        bobTimeline,
        'the deletion',
        (e) => e.eventId == eventId && e.redacted,
      );
      await expectShownAsDeleted(deleted.getDisplayEvent(bobTimeline));
      // Nor does the chat list show the edit
      final preview = await shownText(bobChat.lastEvent!);
      expect(preview, isNot(contains('Rettet versjon')));
      expect(preview, isNot(contains('decrypt')));
    });

    test('a message this phone could not decrypt shows as deleted', () async {
      final eventId = await aliceChat.sendTextEvent('Før den nye telefonen');
      await arrives(bobTimeline, 'the message', (e) => e.eventId == eventId);

      // A new phone without chat backup has no key for it
      final bobsNewPhone = await logIn('bob');
      final chat = await joined(bobsNewPhone, bobChat.id);
      final timeline = await chat.getTimeline();
      final undecryptable = await inHistory(
        timeline,
        'the old message',
        (e) => e.eventId == eventId,
      );
      expect(undecryptable.messageType, MessageTypes.BadEncrypted);

      await aliceChat.redactEvent(eventId!);
      final deleted = await arrives(
        timeline,
        'the deletion',
        (e) => e.eventId == eventId && e.redacted,
      );
      await expectShownAsDeleted(deleted);
      await eventually(
        'the chat list shows the deletion',
        () => chat.lastEvent?.eventId == eventId,
      );
      await expectShownAsDeleted(chat.lastEvent!);
    });
  });
}
