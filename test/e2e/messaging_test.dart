// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Two people writing to each other in an encrypted direct chat: messages,
// edits (and what an edited message said before), replies, reactions,
// typing, emojis, locations, polls (which move down to their newest vote),
// profiles and deleting.

@Timeout(Duration(minutes: 3))
library;

import 'dart:typed_data';
import 'dart:ui' show Locale;

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart' as picker;
import 'package:fluffychat/gruppechat/chat_reading.dart';
import 'package:fluffychat/gruppechat/clock.dart';
import 'package:fluffychat/gruppechat/edit_history.dart';
import 'package:fluffychat/gruppechat/emoji.dart';
import 'package:fluffychat/gruppechat/message_actions.dart';
import 'package:fluffychat/gruppechat/polls.dart';
import 'package:fluffychat/gruppechat/read_positions.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/client_download_content_extension.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:intl/date_symbol_data_local.dart';
import 'package:matrix/matrix.dart';
import 'package:swipe_to_action/swipe_to_action.dart';

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

    test('the time under a message uses the 24-hour clock on a PC', () async {
      await initializeDateFormatting();
      await aliceChat.sendTextEvent('Kor mykje er klokka?');
      final message = await arrives(
        bobTimeline,
        'the message',
        (e) => e.body == 'Kor mykje er klokka?',
      );
      final sent = message.originServerTs;
      String two(int n) => n.toString().padLeft(2, '0');

      // Bob's PC or browser doesn't tell the app how he reads the clock,
      // whether the app itself shows Norwegian or English.
      final in24Hours = showsTimeIn24Hours(
        platform: ClockPlatform.other,
        deviceSays24Hours: false,
      );
      for (final app in ['nb', 'en']) {
        expect(
          timeOfDay(sent, in24Hours: in24Hours, languageCode: app),
          '${two(sent.hour)}:${two(sent.minute)}',
          reason: 'the app in $app',
        );
        expect(
          timeOfDay(
            sent,
            in24Hours: in24Hours,
            languageCode: app,
            seconds: true,
          ),
          '${two(sent.hour)}:${two(sent.minute)}:${two(sent.second)}',
        );
      }

      // An Android phone set to AM/PM keeps it.
      for (final phoneSays24Hours in [true, false]) {
        expect(
          showsTimeIn24Hours(
            platform: ClockPlatform.android,
            deviceSays24Hours: phoneSays24Hours,
          ),
          phoneSays24Hours,
        );
      }
      expect(
        timeOfDay(
          DateTime(2026, 11, 15, 14, 5),
          in24Hours: false,
          languageCode: 'en',
        ),
        '2:05 PM',
      );
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

    test('tapping "(edited)" shows what the message said before', () async {
      final eventId = await aliceChat.sendTextEvent('Møte klokka 18');
      const i18n = MatrixDefaultLocalizations();
      List<String> history() => gruppechatEditHistory(
        bobTimeline.events.firstWhere((e) => e.eventId == eventId),
        bobTimeline,
        i18n,
      ).map((v) => v.text).toList();
      bool edited() => gruppechatWasEdited(
        bobTimeline.events.firstWhere((e) => e.eventId == eventId),
        bobTimeline,
      );

      await arrives(bobTimeline, 'the message', (e) => e.eventId == eventId);
      // Someone else's "edit" changes nothing, so the message isn't edited
      final bobsEdit = await bobChat.sendTextEvent(
        'Bob var her',
        editEventId: eventId,
      );
      await arrives(bobTimeline, "bob's edit", (e) => e.eventId == bobsEdit);
      expect(edited(), isFalse);
      expect(history(), isEmpty);

      await aliceChat.sendTextEvent('Møte klokka 19', editEventId: eventId);
      final second = await aliceChat.sendTextEvent(
        'Møte klokka 19.30',
        editEventId: eventId,
      );
      await eventually('bob sees both edits', () => history().length == 3);
      expect(edited(), isTrue);
      expect(history(), [
        'Møte klokka 18',
        'Møte klokka 19',
        'Møte klokka 19.30',
      ]);
      // The newest is what the chat shows
      expect(
        history().last,
        bobTimeline.events
            .firstWhere((e) => e.eventId == eventId)
            .getDisplayEvent(bobTimeline)
            .body,
      );

      // A deleted edit is gone from the history too
      await aliceChat.redactEvent(second!);
      await eventually(
        'bob sees the edit deleted',
        () => history().length == 2,
      );
      expect(history(), ['Møte klokka 18', 'Møte klokka 19']);

      // And a deleted message keeps nothing of what it said
      await aliceChat.redactEvent(eventId!);
      await eventually('bob sees the message deleted', () => !edited());
      expect(history(), isEmpty);
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

    test(
      'a double tap reacts quickly, and a second one takes it back',
      () async {
        final eventId = await aliceChat.sendTextEvent('Kino på fredag?');
        final question = await arrives(
          bobTimeline,
          'the question',
          (e) => e.eventId == eventId,
        );
        bool aliceSeesHeart() {
          final message = aliceTimeline.events.firstWhere(
            (e) => e.eventId == eventId,
          );
          return message
              .aggregatedEvents(aliceTimeline, RelationshipTypes.reaction)
              .any(
                (r) =>
                    r.senderId == bob.userID &&
                    r.content
                            .tryGetMap<String, Object?>('m.relates_to')
                            ?.tryGet<String>('key') ==
                        '❤️',
              );
        }

        await gruppechatQuickReact(question, bobTimeline, '❤️');
        await eventually('alice sees the heart', aliceSeesHeart);
        await eventually(
          "bob's app knows he reacted",
          () => question
              .aggregatedEvents(bobTimeline, RelationshipTypes.reaction)
              .any((r) => r.senderId == bob.userID && !r.redacted),
        );
        await gruppechatQuickReact(question, bobTimeline, '❤️');
        await eventually('the heart is gone', () => !aliceSeesHeart());
      },
    );

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

    test('a few emojis alone are shown big, without a bubble', () async {
      // As people type them: with a space after, between them, or none
      const big = {
        '🎉': 1,
        '🎉 ': 1,
        '🎉🎉': 2,
        '🎉 🎉 🎉 ': 3,
        '😂😂😂😂😂😂': 6,
      };
      const small = ['🎉🎉🎉🎉🎉🎉🎉', 'Gratulerer 🎉'];
      for (final text in [...big.keys, ...small]) {
        await aliceChat.sendTextEvent(text);
      }
      for (final MapEntry(key: text, value: count) in big.entries) {
        final event = await arrives(bobTimeline, text, (e) => e.body == text);
        expect(event.bigEmojiCount, count, reason: text);
      }
      for (final text in small) {
        final event = await arrives(bobTimeline, text, (e) => e.body == text);
        expect(event.bigEmojiCount, isNull, reason: text);
      }
      final single = await arrives(
        bobTimeline,
        'the emoji',
        (e) => e.body == '🎉',
      );

      // A reply keeps its bubble, which holds the quote
      await bobChat.sendTextEvent('👍', inReplyTo: single);
      final reply = await arrives(
        aliceTimeline,
        'the emoji reply',
        (e) => e.body.endsWith('👍') && e.inReplyToEventId() != null,
      );
      expect(
        reply.bigEmojiCount != null &&
            reply.inReplyToEventId(includingFallback: false) == null,
        isFalse,
      );
    });

    test('🥲 is on the emoji keyboard, and shows big', () async {
      // The smileys of the chat's emoji keyboard, in Norwegian
      final smileys = gruppechatEmojiSet(const Locale('nb'))
          .firstWhere(
            (category) => category.category == picker.Category.SMILEYS,
          )
          .emoji
          .map((emoji) => emoji.emoji);
      expect(smileys, contains('🥲'));
      await aliceChat.sendTextEvent('🥲');
      final event = await arrives(bobTimeline, '🥲', (e) => e.body == '🥲');
      expect(event.bigEmojiCount, 1);
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

    test('your own messages are swiped to the left to reply', () async {
      final own = await aliceChat.sendTextEvent('Svar meg');
      await bobChat.sendTextEvent('Bob spør');
      final mine = await arrives(
        aliceTimeline,
        'her message',
        (e) => e.eventId == own && e.status.isSent,
      );
      final theirs = await arrives(
        aliceTimeline,
        'bob\'s message',
        (e) => e.body == 'Bob spør',
      );
      expect(
        mine.replySwipeDirection(rightToLeftSetting: false),
        SwipeDirection.endToStart,
      );
      expect(
        theirs.replySwipeDirection(rightToLeftSetting: false),
        SwipeDirection.startToEnd,
      );
      // With "swipe right to left to reply" on, every message goes left
      expect(
        theirs.replySwipeDirection(rightToLeftSetting: true),
        SwipeDirection.endToStart,
      );
    });

    test('the mouse over a message offers to reply to it', () async {
      final own = await aliceChat.sendTextEvent('Hover over meg');
      await bobChat.sendTextEvent('Og meg');
      final mine = await arrives(
        aliceTimeline,
        'her message',
        (e) => e.eventId == own && e.status.isSent,
      );
      final theirs = await arrives(
        aliceTimeline,
        'his message',
        (e) => e.body == 'Og meg',
      );
      expect(mine.repliesOnHover, isTrue);
      expect(theirs.repliesOnHover, isTrue);

      // Replying from the button works as from the bottom one
      await aliceChat.sendTextEvent('Svar', inReplyTo: theirs);
      await arrives(
        bobTimeline,
        'the reply',
        (e) => e.inReplyToEventId() == theirs.eventId,
      );

      // A deleted message has nothing to reply to
      await bobChat.redactEvent(theirs.eventId);
      final deleted = await arrives(
        aliceTimeline,
        'the deletion',
        (e) => e.eventId == theirs.eventId && e.redacted,
      );
      expect(deleted.repliesOnHover, isFalse);

      // Where bob can't write, such as a group's space, nothing is offered
      final group = await newGroup(alice, [bob], setUp: false);
      final space = alice.getRoomById(group.spaceId)!;
      final notice = await space.sendTextEvent('Velkommen');
      final bobsSpace = await joined(bob, group.spaceId);
      final bobsView = await arrives(
        await bobsSpace.getTimeline(),
        'the notice',
        (e) => e.eventId == notice,
      );
      expect(bobsSpace.canSendDefaultMessages, isFalse);
      expect(bobsView.repliesOnHover, isFalse);
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
      // Synnøve: the count under each answer is a number, "1 stemme"
      final alicesPoll = aliceTimeline.events.firstWhere(
        (e) => e.eventId == pollId,
      );
      final l10n = await lookupL10n(const Locale('nb'));
      final responses = alicesPoll.getPollResponses(aliceTimeline);
      expect(pollVoters(responses, '2'), {bob.userID});
      expect(pollVoters(responses, '1'), isEmpty);
      expect(l10n.countVotes(pollVoters(responses, '2').length), '1 stemme');
      expect(l10n.countVotes(2), '2 stemmer');
      await alicesPoll.endPoll();
      await eventually(
        'bob sees the poll ended',
        () => bobsPoll().getPollHasBeenEnded(bobTimeline),
      );
    });

    test('a poll moves down to the bottom when someone votes', () async {
      // Tor Helge: nobody should have to scroll far up to find the poll
      final pollId = await aliceChat.startPoll(
        question: 'Kven tek med kaker?',
        answers: [
          PollAnswer(id: '1', mText: 'Eg'),
          PollAnswer(id: '2', mText: 'Ikkje eg'),
        ],
        kind: PollKind.disclosed,
      );
      await aliceChat.sendTextEvent('Svar på spørjeundersøkinga!');
      final poll = await arrives(
        bobTimeline,
        'the poll',
        (e) => e.eventId == pollId,
      );
      await arrives(
        bobTimeline,
        'the message',
        (e) => e.body == 'Svar på spørjeundersøkinga!',
      );
      // As the chat list draws it (lib/pages/chat/chat_event_list.dart)
      List<String> alicesList() =>
          shownInChat(aliceTimeline).take(2).map((e) => e.eventId).toList();
      await arrives(aliceTimeline, 'the poll', (e) => e.eventId == pollId);
      final message = await arrives(
        aliceTimeline,
        'the message',
        (e) => e.body == 'Svar på spørjeundersøkinga!',
      );
      expect(alicesList(), [message.eventId, pollId]);

      // Bob votes: Alice sees the poll at the bottom, the day of the vote
      await poll.answerPoll(['1']);
      await eventually(
        'the poll is at the bottom for alice',
        () => alicesList().first == pollId,
      );
      final moved = <String, Event>{};
      shownInChat(aliceTimeline, moved: moved);
      expect(moved.keys, contains(pollId));

      // Bob's chat marks what he has read, as the chat page does: the newest
      // message that notifies, which is now above the poll. Having voted, his
      // face shows under the poll at the bottom, and he counts among those
      // who have read the poll and the message.
      final target = readMarkerTarget(bobChat, bobTimeline, scrolledUp: false);
      expect(target, isNot(moved[pollId]!.eventId));
      await bobTimeline.setReadMarker(eventId: target, public: true);
      await eventually(
        'alice sees bob under the poll',
        () =>
            gruppechatReadPositions(
              timeline: aliceTimeline,
            )[pollId]?.contains(bob.userID) ??
            false,
      );
      for (final event in [poll, message]) {
        expect(
          gruppechatReadersOf(timeline: aliceTimeline, event: event),
          contains(bob.userID),
        );
      }

      // A message written after the vote comes below the poll
      await bobChat.sendTextEvent('Eg tek med kake.');
      final cake = await arrives(
        aliceTimeline,
        'bob\'s message',
        (e) => e.body == 'Eg tek med kake.',
      );
      expect(alicesList(), [cake.eventId, pollId]);
    });

    test('a banner at the top shows a poll not yet answered', () async {
      // Martin: a banner at the top of the chat when there is a poll one
      // hasn't answered yet. As the chat page asks (lib/gruppechat/
      // poll_banner.dart), with what bob has closed in this chat.
      final closed = <String>{};
      Event? bobsBanner() =>
          unansweredPoll(bobTimeline, bob.userID!, dismissed: closed);

      final pollId = await aliceChat.startPoll(
        question: 'Pizza eller taco?',
        answers: [
          PollAnswer(id: '1', mText: 'Pizza'),
          PollAnswer(id: '2', mText: 'Taco'),
        ],
        kind: PollKind.disclosed,
      );
      final poll = await arrives(
        bobTimeline,
        'the poll',
        (e) => e.eventId == pollId,
      );
      await arrives(aliceTimeline, 'the poll', (e) => e.eventId == pollId);
      expect(bobsBanner()?.eventId, pollId);
      // Alice's own poll doesn't ask her to answer it
      expect(unansweredPoll(aliceTimeline, alice.userID!), isNull);

      // Closing the banner hides it for that poll
      closed.add(poll.eventId);
      expect(bobsBanner(), isNull);
      closed.clear();

      // Voting takes it away
      await poll.answerPoll(['2']);
      await eventually('bob\'s banner is gone', () => bobsBanner() == null);

      // So does the poll being ended before bob has answered
      final secondId = await aliceChat.startPoll(
        question: 'Kino på laurdag?',
        answers: [
          PollAnswer(id: '1', mText: 'Ja'),
          PollAnswer(id: '2', mText: 'Nei'),
        ],
        kind: PollKind.disclosed,
      );
      await arrives(
        bobTimeline,
        'the second poll',
        (e) => e.eventId == secondId,
      );
      expect(bobsBanner()?.eventId, secondId);
      final second = await arrives(
        aliceTimeline,
        'the second poll',
        (e) => e.eventId == secondId,
      );
      await second.endPoll();
      await eventually(
        'the ended poll has no banner',
        () => bobsBanner() == null,
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
