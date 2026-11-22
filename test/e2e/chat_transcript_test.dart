// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Downloading a whole chat as a Markdown file from the chat's settings
// (lib/gruppechat/chat_transcript.dart): dora and erik, two new accounts so
// the chat holds only what this test sends, chat in an encrypted direct
// chat with everything a chat has (a reply, several lines, an edit, a
// deletion, a photo, a thread, a message that disappears and more messages
// than one page of history). Erik then downloads it, and so does a new
// device of his that has none of the keys. While the chat blocks
// screenshots, neither can download it. Saving the file (Downloads on
// Android, the browser's download, the save dialog) can only be tried on a
// phone or in a browser.

@Timeout(Duration(minutes: 5))
library;

import 'dart:ui' show Locale;

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/gruppechat/chat_transcript.dart';
import 'package:fluffychat/gruppechat/message_lifetime.dart';
import 'package:fluffychat/gruppechat/screenshot_block.dart';
import 'package:fluffychat/gruppechat/user_ids.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/test_server.dart';

void main() {
  group('Downloading a chat', skip: skipWithoutTestServer, () {
    late L10n l10n;
    late Client dora;
    late Client erik;
    late String erikPassword;
    late Room doraChat;
    late Room erikChat;
    late Timeline erikTimeline;
    late String transcript;
    late DateTime lastSent;
    // More than a page of history, both from this device and the server
    const many = 120;

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      await AppSettings.init(loadWebConfigFile: false);
      await initializeDateFormatting();
      l10n = await lookupL10n(const Locale('nb'));
      final alice = await logIn('alice');
      (dora, _) = await signUpNewAccount(alice, 'dora');
      (erik, erikPassword) = await signUpNewAccount(alice, 'erik');
      // As the settings page does
      await dora.setProfileField(dora.userID!, 'displayname', {
        'displayname': 'Dora',
      });
      // As the settings page does
      await erik.setProfileField(erik.userID!, 'displayname', {
        'displayname': 'Erik',
      });
      (doraChat, erikChat) = await directChat(dora, erik);
      erikTimeline = await erikChat.getTimeline();
    });
    tearDownAll(logOutEveryone);

    Future<Event> erikGets(String what, String eventId) =>
        arrives(erikTimeline, what, (e) => e.eventId == eventId);

    test('dora and erik chat the way people do', () async {
      final hello = (await doraChat.sendTextEvent('Hei Erik!'))!;
      final helloEvent = await erikGets('the greeting', hello);
      await erikChat.sendTextEvent('Hei Dora!', inReplyTo: helloEvent);
      await doraChat.sendTextEvent('Handleliste:\n# egg\n- melk');

      // An edit, as the chat's input field sends it
      final draft = (await doraChat.sendTextEvent('Vi sees klokka 7'))!;
      await doraChat.sendTextEvent('Vi sees klokka 8', editEventId: draft);

      // A message erik deletes
      final oops = (await erikChat.sendTextEvent('Oops, feil chat'))!;
      await erikGets('his own message', oops);
      await erikChat.redactEvent(oops);

      await doraChat.sendFileEvent(
        MatrixImageFile(
          bytes: img.encodePng(
            img.fill(
              img.Image(width: 40, height: 30),
              color: img.ColorRgb8(30, 120, 200),
            ),
          ),
          name: 'ferie.png',
          mimeType: 'image/png',
        ),
      );

      await erikChat.sendTextEvent(
        'Svar i tråden',
        threadRootEventId: hello,
        threadLastEventId: hello,
      );

      for (var i = 1; i <= many; i++) {
        await doraChat.sendTextEvent('Melding $i');
      }
      final last = (await doraChat.sendTextEvent('Ha det!'))!;
      lastSent = (await erikGets('the last message', last)).originServerTs;
      // Last, a message that disappears, gone before the download. The
      // lifetime stays on: turning it off again would hide everything sent
      // before it was turned on, in the chat as here (gruppechatExpiresAt
      // in lib/gruppechat/message_lifetime.dart only knows the latest
      // change).
      const lifetime = Duration(seconds: 5);
      await gruppechatSetMessageLifetime(doraChat, lifetime);
      await eventually(
        'erik sees the lifetime',
        () => gruppechatMessageLifetime(erikChat) == lifetime,
      );
      final secret = (await doraChat.sendTextEvent('Hemmelig'))!;
      final secretEvent = await erikGets('the secret', secret);
      await eventually(
        'the secret is gone',
        () => gruppechatIsGone(secretEvent),
        timeout: const Duration(seconds: 20),
      );
    });

    test('erik downloads it all from the chat settings', () async {
      expect(gruppechatCanDownloadTranscript(erikChat), isTrue);
      // A fresh look at the chat doesn't hold it all; the download pages
      // back through the history
      final fresh = await erikChat.getTimeline();
      expect(fresh.events.length, lessThan(many));
      fresh.cancelSubscriptions();

      final progress = <double?>[];
      transcript = await buildChatTranscript(
        erikChat,
        l10n,
        onProgress: progress.add,
      );
      printOnFailure(transcript);
      expect(progress, isNotEmpty);

      // The day of the last message has its heading
      final today = DateFormat.yMMMMEEEEd('nb').format(lastSent);
      const time = r'\(\d\d:\d\d';
      final lines = transcript.split('\n');
      expect(lines.first, '# Dora');
      expect(lines[2], startsWith('Lastet ned '));
      expect(
        lines[2],
        endsWith('av Erik (${erik.displayUserId(erik.userID!)}).'),
      );
      expect(
        transcript,
        contains('## ${today[0].toUpperCase()}${today.substring(1)}'),
      );
      expect(
        transcript,
        matches(
          RegExp('^\\*\\*Dora\\*\\* $time\\): Hei Erik!\$', multiLine: true),
        ),
      );
      expect(
        transcript,
        matches(
          RegExp(
            '^\\*\\*Erik\\*\\* $time, svar til Dora: «Hei Erik!»\\): Hei Dora!\$',
            multiLine: true,
          ),
        ),
      );
      expect(
        transcript,
        matches(
          RegExp(
            '^\\*\\*Dora\\*\\* $time\\):\n'
            '> Handleliste:  \n'
            r'> \\# egg  '
            '\n'
            r'> \\- melk$',
            multiLine: true,
          ),
        ),
        reason: 'several lines keep their lines, and stay text',
      );
      expect(transcript, contains('): Vi sees klokka 8 _(redigert)_'));
      expect(transcript, isNot(contains('klokka 7')));
      expect(transcript, contains('**Erik** ('));
      expect(transcript, contains('): _🗑️ Slettet av Erik_'));
      expect(transcript, isNot(contains('feil chat')));
      expect(transcript, contains('): 📷 Bilde: ferie.png'));
      expect(
        transcript,
        matches(
          RegExp(
            '^\\*\\*Erik\\*\\* $time, i tråden «Hei Erik!»\\): Svar i tråden\$',
            multiLine: true,
          ),
        ),
      );
      expect(transcript, isNot(contains('Hemmelig')));
      expect(transcript, isNot(contains(l10n.messageNotDecryptable)));

      // Everything, oldest first
      final order = [
        'Hei Erik!',
        'Hei Dora!',
        'Handleliste:',
        'klokka 8',
        'ferie.png',
        'Svar i tråden',
        for (var i = 1; i <= many; i++) ': Melding $i\n',
        'Ha det!',
      ].map(transcript.indexOf).toList();
      expect(order, isNot(contains(-1)));
      expect(order, orderedEquals([...order]..sort()));
    });

    test('a device without the keys says what it cannot read', () async {
      final newDevice = await logIn(
        erik.userID!.localpart!,
        password: erikPassword,
      );
      final room = await joined(newDevice, erikChat.id);
      final markdown = await buildChatTranscript(room, l10n);
      printOnFailure(markdown);
      expect(markdown.split('\n').first, '# Dora');
      expect(markdown, contains(l10n.messageNotDecryptable));
      expect(markdown, contains('): _🗑️ Slettet av Erik_'));
      expect(markdown, isNot(contains('Hemmelig')));
      // Every message is there, paged from the server, named as on erik's
      // first device
      int messages(String text) =>
          RegExp(r'^\*\*Dora\*\* \(', multiLine: true).allMatches(text).length;
      expect(messages(markdown), messages(transcript));
    });

    test('while dora blocks screenshots, nobody can download it, and the '
        'block leaves no trace in the file', () async {
      // Unknown events shown too, so a trace would show
      await AppSettings.hideUnknownEvents.setItem(false);
      addTearDown(() => AppSettings.hideUnknownEvents.setItem(true));
      final downloadedAt = DateTime(2026, 11, 22, 12);
      final before = await buildChatTranscript(
        erikChat,
        l10n,
        now: downloadedAt,
      );

      // From the chat's settings (lib/gruppechat/screenshot_block.dart)
      await gruppechatSetScreenshotBlock(doraChat, true);
      await eventually(
        'erik sees the block',
        () => gruppechatScreenshotsBlocked(erikChat),
      );
      for (final room in [doraChat, erikChat]) {
        expect(gruppechatCanDownloadTranscript(room), isFalse);
        await expectLater(
          buildChatTranscript(room, l10n),
          throwsA(isA<TranscriptRefused>()),
        );
      }

      await gruppechatSetScreenshotBlock(doraChat, false);
      await eventually(
        'erik sees it lifted',
        () => !gruppechatScreenshotsBlocked(erikChat),
      );
      expect(gruppechatCanDownloadTranscript(erikChat), isTrue);
      final after = await buildChatTranscript(
        erikChat,
        l10n,
        now: downloadedAt,
      );
      expect(after, before);
      expect(after, isNot(contains(gruppechatScreenshotsType)));
    });
  });
}
