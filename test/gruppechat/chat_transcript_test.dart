// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// A chat downloaded as a Markdown file (lib/gruppechat/chat_transcript.dart):
// its file name, how messages read in it, and that what people write never
// breaks the file's own structure. test/e2e/chat_transcript_test.dart
// downloads real chats.

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/gruppechat/change_notices.dart';
import 'package:fluffychat/gruppechat/chat_transcript.dart';
import 'package:fluffychat/gruppechat/message_lifetime.dart';
import 'package:fluffychat/gruppechat/screenshot_block.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
// ignore: implementation_imports
import 'package:matrix/src/models/timeline_chunk.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/test_client.dart';

void main() {
  late L10n l10n;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    await initializeDateFormatting();
    l10n = await lookupL10n(const Locale('nb'));
  });

  group('the file name', () {
    final day = DateTime(2026, 11, 21, 14, 3);

    test('has the chat name and the date', () {
      expect(
        chatTranscriptFileName('Alice og Bob', day),
        'Hanne-Chat-Alice-og-Bob-2026-11-21.md',
      );
    });

    test('keeps letters, drops what file systems refuse', () {
      expect(
        chatTranscriptFileName('Bjørn: «Hytta» 2/3 ✨', day),
        'Hanne-Chat-Bjørn-Hytta-2-3-2026-11-21.md',
      );
      expect(
        chatTranscriptFileName(r'a\b*c?"d<e>f|g', day),
        'Hanne-Chat-a-b-c-d-e-f-g-2026-11-21.md',
      );
      expect(
        chatTranscriptFileName('🎉🎉', day),
        'Hanne-Chat-Chat-2026-11-21.md',
      );
      final long = chatTranscriptFileName('a' * 200, day);
      expect(long, 'Hanne-Chat-${'a' * 60}-2026-11-21.md');
    });
  });

  group('a line of text', () {
    test('that would be structure stays text', () {
      final cases = {
        '# ikke en overskrift': r'\# ikke en overskrift',
        '###': r'\###',
        '> ikke et sitat': r'\> ikke et sitat',
        '- melk': r'\- melk',
        '* egg': r'\* egg',
        '+ brød': r'\+ brød',
        '1. først': r'1\. først',
        '2026) slutt': r'2026\) slutt',
        '---': r'\---',
        '- - -': r'\- - -',
        '***': r'\***',
        '___': r'\___',
        '===': r'\===',
        '|---|---|': r'\|---|---|',
        '```dart': r'\```dart',
        '~~~': r'\~~~',
        '[lenke]: https://example.org': r'\[lenke]: https://example.org',
        '<script>alert(1)</script>': r'\<script>alert(1)\</script>',
        '<!-- skjult -->': r'\<!-- skjult -->',
      };
      for (final MapEntry(key: line, value: escaped) in cases.entries) {
        expect(markdownText(line), escaped, reason: line);
      }
    });

    test('that is just text stays as it was written', () {
      for (final line in [
        '#hashtag',
        '-5 grader ute',
        '2026 var et godt år',
        'Det koster 3.50',
        'Jeg <3 deg',
        'a < b og b > c',
        '**fet** og _kursiv_',
        'Se https://example.org/a_b',
      ]) {
        expect(markdownText(line), line);
      }
    });

    test('keeps its indentation without becoming code', () {
      expect(markdownText('    kode()'), '    kode()');
      expect(markdownText('\t# inn'), '${' ' * 4}\\# inn');
    });

    test('inside a line, only HTML is escaped', () {
      expect(markdownText('# ja', startsLine: false), '# ja');
      expect(
        markdownText('se <b>dette</b>', startsLine: false),
        r'se \<b>dette\</b>',
      );
    });

    test('names and the app\'s words mean no formatting', () {
      expect(markdownInline('*Stjerne* _Ola_'), r'\*Stjerne\* \_Ola\_');
      expect(
        markdownInline('[Ola](x) #1 `k` ~a~ <b>'),
        r'\[Ola\](x) \#1 \`k\` \~a\~ \<b>',
      );
      expect(markdownInline('to\nlinjer'), 'to linjer');
    });
  });

  group('a message', () {
    final time = DateTime(2026, 11, 20, 9, 5);
    String md(TranscriptItem item) =>
        transcriptItemMarkdown(item, '09:05', l10n.edited);

    test('of one line follows the name and time', () {
      expect(
        md(TranscriptItem(time: time, sender: 'Alice', text: 'Hei Bob!')),
        '**Alice** (09:05): Hei Bob!',
      );
    });

    test('of several lines is a block quote that keeps its lines', () {
      expect(
        md(
          TranscriptItem(
            time: time,
            sender: 'Bob',
            text: '\nHandleliste:\n# egg\n- melk\n\n1. brød\n\n',
          ),
        ),
        '**Bob** (09:05):\n'
        '> Handleliste:  \n'
        '> \\# egg  \n'
        '> \\- melk\n'
        '>\n'
        '> 1\\. brød',
      );
    });

    test('says what it answers, and that it was edited', () {
      expect(
        md(
          TranscriptItem(
            time: time,
            sender: 'Bob',
            text: 'Ja!',
            context: l10n.gruppechatTranscriptReplyTo('Alice', 'Kommer du?'),
            edited: true,
          ),
        ),
        '**Bob** (09:05, svar til Alice: «Kommer du?»): Ja! _(redigert)_',
      );
      expect(
        md(
          TranscriptItem(
            time: time,
            sender: 'Bob',
            text: 'En\nTo',
            context: l10n.gruppechatTranscriptInThread('Pizza?'),
            edited: true,
          ),
        ),
        '**Bob** (09:05, i tråden «Pizza?»):\n> En  \n> To _(redigert)_',
      );
    });

    test('in the app\'s words is in italics', () {
      expect(
        md(
          TranscriptItem(
            time: time,
            sender: 'Bob',
            text: '🗑️ ${l10n.redactedBy('Bob')}',
            note: true,
          ),
        ),
        '**Bob** (09:05): _🗑️ Slettet av Bob_',
      );
    });

    test('a line about the chat has no name', () {
      expect(
        md(TranscriptItem(time: time, text: 'Alice_99 ble med')),
        r'_Alice\_99 ble med_ (09:05)',
      );
    });

    test('a name can\'t break the bold', () {
      expect(
        md(TranscriptItem(time: time, sender: '**Ola**', text: 'Hei')),
        r'**\*\*Ola\*\*** (09:05): Hei',
      );
    });
  });

  test('the file: the chat, who downloaded it, and a heading per day', () {
    final markdown = chatTranscriptMarkdown(
      l10n,
      chatName: 'Alice og Bob',
      downloadedBy: 'Bob (@bob)',
      downloadedAt: DateTime(2026, 11, 21, 14, 3),
      items: [
        TranscriptItem(time: DateTime(2026, 11, 20, 23, 59), text: 'Start'),
        TranscriptItem(
          time: DateTime(2026, 11, 20, 23, 59, 30),
          sender: 'Alice',
          text: 'God natt',
        ),
        TranscriptItem(
          time: DateTime(2026, 11, 21, 7, 1),
          sender: 'Bob',
          text: 'God morgen',
        ),
      ],
    );
    expect(
      markdown,
      '# Alice og Bob\n'
      '\n'
      'Lastet ned 21. november 2026 14:03 av Bob (@bob).\n'
      '\n'
      '## Fredag 20. november 2026\n'
      '\n'
      '_Start_ (23:59)\n'
      '\n'
      '**Alice** (23:59): God natt\n'
      '\n'
      '## Lørdag 21. november 2026\n'
      '\n'
      '**Bob** (07:01): God morgen\n',
    );
  });

  group('from the events of a chat', () {
    late Client client;
    late Room room;
    const alice = '@alice:example.invalid';
    const bob = '@bob:example.invalid';
    var n = 0;

    setUpAll(() async {
      client = await prepareTestClient(loggedIn: true);
      room = Room(id: '!chat:example.invalid', client: client);
      for (final (id, name) in [(alice, 'Alice'), (bob, 'Bob')]) {
        room.setState(
          Event(
            type: EventTypes.RoomMember,
            content: {'membership': 'join', 'displayname': name},
            senderId: id,
            stateKey: id,
            eventId: '\$member$id',
            originServerTs: DateTime(2026, 11, 20, 8),
            room: room,
          ),
        );
      }
    });

    Event event(
      String id,
      String type,
      Map<String, Object?> content, {
      String sender = alice,
      String? stateKey,
      Map<String, Object?>? unsigned,
      EventStatus status = EventStatus.synced,
    }) => Event(
      type: type,
      content: content,
      eventId: '\$$id',
      senderId: sender,
      stateKey: stateKey,
      unsigned: unsigned,
      originServerTs: DateTime(2026, 11, 20, 9, n++),
      status: status,
      room: room,
    );
    Event text(
      String id,
      String body, {
      String sender = alice,
      Map? relates,
      EventStatus status = EventStatus.synced,
    }) => event(
      id,
      EventTypes.Message,
      {'msgtype': MessageTypes.Text, 'body': body, 'm.relates_to': ?relates},
      sender: sender,
      status: status,
    );

    test('reads as the chat shows them', () {
      final redaction = event('del', EventTypes.Redaction, {}, sender: bob);
      final events = [
        text('hei', 'Hei Bob!'),
        text(
          'svar',
          'Hei Alice!',
          sender: bob,
          relates: {
            'm.in_reply_to': {'event_id': r'$hei'},
          },
        ),
        text('utkast', 'Vi sees klokka 7'),
        text(
            'rettet',
            '* Vi sees klokka 8',
            relates: {
              'rel_type': RelationshipTypes.edit,
              'event_id': r'$utkast',
            },
          )
          ..content['m.new_content'] = {
            'msgtype': MessageTypes.Text,
            'body': 'Vi sees klokka 8',
          },
        event(
          'slettet',
          EventTypes.Message,
          {},
          sender: bob,
          unsigned: {'redacted_because': redaction.toJson()},
        ),
        text(
          'tråd',
          'Svar i tråden',
          sender: bob,
          relates: {
            'rel_type': RelationshipTypes.thread,
            'event_id': r'$hei',
            'is_falling_back': true,
            'm.in_reply_to': {'event_id': r'$hei'},
          },
        ),
        event('bilde', EventTypes.Message, {
          'msgtype': MessageTypes.Image,
          'body': 'Fra ferien',
          'filename': 'ferie.png',
          'url': 'mxc://example.invalid/ferie',
        }),
        event('fil', EventTypes.Message, {
          'msgtype': MessageTypes.File,
          'body': 'liste.txt',
          'url': 'mxc://example.invalid/liste',
        }, sender: bob),
        event('låst', EventTypes.Encrypted, {
          'msgtype': MessageTypes.BadEncrypted,
          'body': DecryptException.unknownSession,
          'can_request_session': true,
          'session_id': 'x',
        }, sender: bob),
        event('farge', gruppechatChangeType, {'kind': 'chat_color'}),
        event('reaksjon', EventTypes.Reaction, {
          'm.relates_to': {
            'rel_type': RelationshipTypes.reaction,
            'event_id': r'$hei',
            'key': '👍',
          },
        }, sender: bob),
        text('ikke sendt', 'Feilet', status: EventStatus.error),
        // The chat got a lifetime of a minute, which the chat doesn't show,
        event(
          'levetid',
          gruppechatLifetimeType,
          {'lifetime': 60000},
          stateKey: '',
          unsigned: {'prev_content': <String, Object?>{}},
        ),
        // and a message sent then is long gone
        text('borte', 'Forsvant'),
      ];
      final timeline = Timeline(
        room: room,
        chunk: TimelineChunk(events: events.reversed.toList()),
      );
      room.setState(events.firstWhere((e) => e.eventId == r'$levetid'));

      final items = chatTranscriptItems(timeline, l10n);
      String line(TranscriptItem item) =>
          transcriptItemMarkdown(item, 'tid', l10n.edited);
      expect(items.map(line).toList(), [
        '**Alice** (tid): Hei Bob!',
        '**Bob** (tid, svar til Alice: «Hei Bob!»): Hei Alice!',
        '**Alice** (tid): Vi sees klokka 8 _(redigert)_',
        '**Bob** (tid): _🗑️ Slettet av Bob_',
        '**Bob** (tid, i tråden «Hei Bob!»): Svar i tråden',
        '**Alice** (tid):\n> 📷 Bilde: ferie.png  \n> Fra ferien',
        '**Bob** (tid): 📎 Fil: liste.txt',
        '**Bob** (tid): _Meldingen kan ikke dekrypteres_',
        '_${markdownInline(l10n.gruppechatChangedChatColor('Alice'))}_ (tid)',
      ]);
      // Oldest first, at the time each was sent
      expect(items.first.time, DateTime(2026, 11, 20, 9, 1));
      expect(
        MatrixLocals(l10n).you,
        isNotEmpty,
        reason: 'the chat\'s own words come from the app',
      );
    });

    test('blocking screenshots leaves no line, even with unknown events '
        'shown', () async {
      await AppSettings.hideUnknownEvents.setItem(false);
      addTearDown(() => AppSettings.hideUnknownEvents.setItem(true));
      // Without the lifetime of the test before, which would hide them all
      room.states.remove(gruppechatLifetimeType);
      final events = [
        text('foer', 'Før'),
        event(
          'blokk',
          gruppechatScreenshotsType,
          {'blocked': true},
          sender: bob,
          stateKey: bob,
        ),
        event('av', gruppechatScreenshotsType, {}, sender: bob, stateKey: bob),
        text('etter', 'Etter'),
      ];
      final timeline = Timeline(
        room: room,
        chunk: TimelineChunk(events: events.reversed.toList()),
      );
      final items = chatTranscriptItems(timeline, l10n);
      expect(items.map((item) => item.text), ['Før', 'Etter']);
    });
  });
}
