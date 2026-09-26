// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/gruppechat/group_state.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeStateReader implements GroupStateReader {
  final Map<String, Map<String, (String, Map<String, Object?>)>> _states = {};

  void set(
    String type,
    String stateKey,
    Map<String, Object?> content, {
    String sender = '@admin:example.org',
  }) => (_states[type] ??= {})[stateKey] = (sender, content);

  @override
  Map<String, Object?>? content(String type, [String stateKey = '']) =>
      _states[type]?[stateKey]?.$2;

  @override
  String? sender(String type, [String stateKey = '']) =>
      _states[type]?[stateKey]?.$1;

  @override
  Iterable<String> stateKeys(String type) =>
      _states[type]?.keys ?? const <String>[];
}

void main() {
  const alice = '@alice:example.org';
  const bob = '@bob:example.org';

  group('state keys', () {
    test('user keys never start with @', () {
      expect(userStateKey(alice), 'user:@alice:example.org');
      expect(userStateKey(alice).startsWith('@'), isFalse);
    });

    test('round trip', () {
      expect(userIdFromStateKey(userStateKey(bob)), bob);
      expect(userIdFromStateKey(bob), isNull);
      expect(userIdFromStateKey(''), isNull);
    });
  });

  group('colors', () {
    test('parses #RRGGBB as opaque', () {
      expect(parseHexColor('#E91E63'), 0xFFE91E63);
      expect(parseHexColor('e91e63'), 0xFFE91E63);
    });

    test('parses #AARRGGBB', () {
      expect(parseHexColor('#80E91E63'), 0x80E91E63);
    });

    test('rejects invalid values', () {
      expect(parseHexColor('#12345'), isNull);
      expect(parseHexColor('#GGGGGG'), isNull);
      expect(parseHexColor(42), isNull);
      expect(parseHexColor(null), isNull);
    });

    test('formats back', () {
      expect(formatHexColor(0xFFE91E63), '#E91E63');
      expect(formatHexColor(0x80E91E63), '#80E91E63');
      expect(formatHexColor(0xFF000000), '#000000');
    });
  });

  group('roles', () {
    late FakeStateReader reader;
    late GroupState state;

    setUp(() {
      reader = FakeStateReader()
        ..set(GruppechatEventTypes.role, 'gamers', {
          'name': 'Gamers',
          'color': '#00FF00',
        })
        ..set(GruppechatEventTypes.role, 'admins', {'name': 'Admins'})
        ..set(GruppechatEventTypes.role, 'deleted', {})
        ..set(GruppechatEventTypes.role, 'quiet', {
          'name': 'Quiet',
          'mentionable': false,
        })
        ..set(GruppechatEventTypes.memberRoles, userStateKey(alice), {
          'roles': ['admins', 'gamers', 'deleted', 'unknown'],
        })
        ..set(GruppechatEventTypes.memberRoles, userStateKey(bob), {
          'roles': ['gamers'],
        });
      state = GroupState(reader);
    });

    test('lists existing roles sorted by name', () {
      expect(state.roles.map((role) => role.id), ['admins', 'gamers', 'quiet']);
    });

    test('parses role fields', () {
      final gamers = state.roleById('gamers')!;
      expect(gamers.name, 'Gamers');
      expect(gamers.color, 0xFF00FF00);
      expect(gamers.mentionable, isTrue);
      expect(state.roleById('quiet')!.mentionable, isFalse);
      expect(state.roleById('deleted'), isNull);
    });

    test('ignores deleted and unknown roles in assignments', () {
      expect(state.roleIdsOf(alice), {'admins', 'gamers'});
      expect(state.roleIdsOf('@nobody:example.org'), isEmpty);
    });

    test('finds members with a role', () {
      expect(state.membersWithRole('gamers'), unorderedEquals([alice, bob]));
      expect(state.membersWithRole('admins'), [alice]);
      expect(state.membersWithRole('deleted'), isEmpty);
    });

    test('role content round trip', () {
      const role = GroupRole(id: 'mods', name: 'Mods', color: 0xFF123456);
      final parsed = GroupRole.fromContent('mods', role.toContent())!;
      expect(parsed.name, 'Mods');
      expect(parsed.color, 0xFF123456);
      expect(parsed.mentionable, isTrue);
    });
  });

  group('role mentions', () {
    const roles = [
      GroupRole(id: 'admins', name: 'Admins'),
      GroupRole(id: 'game-night', name: 'Game night'),
      GroupRole(id: 'quiet', name: 'Quiet', mentionable: false),
    ];

    test('matches the ID and the name, case-insensitively', () {
      expect(mentionedRoleIds('@admins pin this', roles), {'admins'});
      expect(mentionedRoleIds('hey @ADMINS!', roles), {'admins'});
      expect(mentionedRoleIds('@Game night tonight?', roles), {'game-night'});
      expect(mentionedRoleIds('@game-night', roles), {'game-night'});
    });

    test('needs a clean boundary', () {
      expect(mentionedRoleIds('mail me at x@admins.org', roles), isEmpty);
      expect(mentionedRoleIds('@adminsfoo', roles), isEmpty);
      expect(mentionedRoleIds('@admins:example.org', roles), isEmpty);
      expect(mentionedRoleIds('admins', roles), isEmpty);
    });

    test('ignores roles that are not mentionable', () {
      expect(mentionedRoleIds('@quiet please', roles), isEmpty);
    });

    test('only notifies for your own roles', () {
      expect(mentionsAnyRole('@admins look', roles, {'admins'}), isTrue);
      expect(mentionsAnyRole('@admins look', roles, {'game-night'}), isFalse);
      expect(mentionsAnyRole('@admins look', roles, {}), isFalse);
    });
  });

  group('role IDs', () {
    test('slugifies names', () {
      expect(roleIdFromName('Game Night!', []), 'game-night');
      expect(roleIdFromName('  Admins  ', []), 'admins');
    });

    test('transliterates Norwegian letters', () {
      expect(roleIdFromName('Gæster på Lørdag', []), 'gaester-pa-lordag');
    });

    test('falls back and stays unique', () {
      expect(roleIdFromName('!!!', []), 'role');
      expect(roleIdFromName('Admins', ['admins']), 'admins-2');
      expect(roleIdFromName('Admins', ['admins', 'admins-2']), 'admins-3');
    });
  });

  group('nicknames', () {
    test('anyone can name anyone', () {
      final reader = FakeStateReader()
        ..set(GruppechatEventTypes.nickname, userStateKey(bob), {
          'name': ' Captain ',
          'emoji': '🧭',
        }, sender: alice);
      final nickname = GroupState(reader).nicknameOf(bob)!;
      expect(nickname.name, 'Captain');
      expect(nickname.displayName, 'Captain 🧭');
      expect(nickname.setBy, alice);
    });

    test('empty content clears the nickname', () {
      final reader = FakeStateReader()
        ..set(GruppechatEventTypes.nickname, userStateKey(bob), {});
      expect(GroupState(reader).nicknameOf(bob), isNull);
    });

    test('a lock hides nicknames set by others', () {
      final reader = FakeStateReader()
        ..set(GruppechatEventTypes.nickname, userStateKey(bob), {
          'name': 'Captain',
        }, sender: alice)
        ..set(GruppechatEventTypes.nicknameLock, bob, {
          'locked': true,
        }, sender: bob);
      final state = GroupState(reader);
      expect(state.isNicknameLocked(bob), isTrue);
      expect(state.nicknameOf(bob), isNull);
    });

    test('a lock keeps the nickname you set yourself', () {
      final reader = FakeStateReader()
        ..set(GruppechatEventTypes.nickname, userStateKey(bob), {
          'name': 'Bobby',
        }, sender: bob)
        ..set(GruppechatEventTypes.nicknameLock, bob, {
          'locked': true,
        }, sender: bob);
      expect(GroupState(reader).nicknameOf(bob)!.name, 'Bobby');
    });

    test('content helper trims and drops empty emoji', () {
      expect(GroupNickname.contentFor(' Captain ', emoji: ' '), {
        'name': 'Captain',
      });
    });
  });

  group('backgrounds', () {
    test('parses a gradient', () {
      final background = GroupBackground.fromContent({
        'kind': 'gradient',
        'colors': ['#FF6B6B', '#556270'],
        'rotation': 135,
        'opacity': 60,
      })!;
      expect(background.kind, GroupBackgroundKind.gradient);
      expect(background.colors, [0xFFFF6B6B, 0xFF556270]);
      expect(background.rotation, 135);
      expect(background.opacity, 0.6);
    });

    test('clamps opacity and blur', () {
      final background = GroupBackground.fromContent({
        'kind': 'solid',
        'colors': ['#000000'],
        'opacity': 300,
        'blur': 500,
      })!;
      expect(background.opacity, 1);
      expect(background.blur, 50);
    });

    test('rejects cleared and invalid content', () {
      expect(GroupBackground.fromContent(null), isNull);
      expect(GroupBackground.fromContent({}), isNull);
      expect(GroupBackground.fromContent({'kind': 'sparkles'}), isNull);
      expect(GroupBackground.fromContent({'kind': 'solid'}), isNull);
      expect(
        GroupBackground.fromContent({
          'kind': 'gradient',
          'colors': ['#000000'],
        }),
        isNull,
      );
      expect(GroupBackground.fromContent({'kind': 'image'}), isNull);
    });

    test('content round trip', () {
      final image = GroupBackground(
        kind: GroupBackgroundKind.image,
        url: Uri.parse('mxc://example.org/abc'),
        opacity: 0.5,
        blur: 4,
      );
      final parsed = GroupBackground.fromContent(image.toContent())!;
      expect(parsed.kind, GroupBackgroundKind.image);
      expect(parsed.url.toString(), 'mxc://example.org/abc');
      expect(parsed.opacity, 0.5);
      expect(parsed.blur, 4);
    });

    test('content never contains floats, which Matrix rejects', () {
      final contents = [
        for (final (_, preset) in groupBackgroundPresets) preset.toContent(),
        const GroupBackground(
          kind: GroupBackgroundKind.solid,
          colors: [0xFF000000],
          opacity: 0.33,
          blur: 2.5,
        ).toContent(),
      ];
      for (final content in contents) {
        expect(content.values.whereType<double>(), isEmpty, reason: '$content');
      }
      expect(contents.last['opacity'], 33);
      expect(contents.last['blur'], 3);
    });

    test('every preset is valid and survives a round trip', () {
      for (final (name, preset) in groupBackgroundPresets) {
        expect(preset.isValid, isTrue, reason: name);
        expect(
          GroupBackground.fromContent(preset.toContent())?.colors,
          preset.colors,
          reason: name,
        );
      }
    });

    test('a channel overrides the group and none clears it', () {
      const group = GroupBackground(
        kind: GroupBackgroundKind.solid,
        colors: [0xFF000000],
      );
      const channel = GroupBackground(
        kind: GroupBackgroundKind.solid,
        colors: [0xFFFFFFFF],
      );
      const none = GroupBackground(kind: GroupBackgroundKind.none);
      expect(resolveGroupBackground(group: group), group);
      expect(resolveGroupBackground(channel: channel, group: group), channel);
      expect(resolveGroupBackground(channel: none, group: group), isNull);
      expect(resolveGroupBackground(group: group, enabled: false), isNull);
      expect(resolveGroupBackground(), isNull);
    });

    test('the group background is read from state', () {
      final reader = FakeStateReader()
        ..set(GruppechatEventTypes.background, '', {
          'kind': 'solid',
          'colors': ['#1B1F3B'],
        });
      expect(GroupState(reader).background?.colors, [0xFF1B1F3B]);
    });
  });

  group('power levels', () {
    test('adds missing event types and keeps existing values', () {
      final merged = withGroupPowerLevels({
        'users': {alice: 100},
        'events': {'m.room.name': 50, GruppechatEventTypes.background: 50},
        'state_default': 50,
      });
      final events = merged['events']! as Map<String, Object?>;
      expect(merged['users'], {alice: 100});
      expect(merged['state_default'], 50);
      expect(events['m.room.name'], 50);
      expect(events[GruppechatEventTypes.background], 50);
      expect(events[GruppechatEventTypes.nickname], 0);
      expect(events[GruppechatEventTypes.role], 50);
      expect(hasGroupPowerLevels(merged), isTrue);
    });

    test('detects missing setup', () {
      expect(hasGroupPowerLevels(null), isFalse);
      expect(hasGroupPowerLevels({}), isFalse);
      expect(
        hasGroupPowerLevels({
          'events': {GruppechatEventTypes.role: 50},
        }),
        isFalse,
      );
    });

    test('moderators manage roles, everyone else can style and rename', () {
      expect(groupEventPowerLevels[GruppechatEventTypes.role], 50);
      expect(groupEventPowerLevels[GruppechatEventTypes.memberRoles], 50);
      expect(groupEventPowerLevels[GruppechatEventTypes.nickname], 0);
      expect(groupEventPowerLevels[GruppechatEventTypes.nicknameLock], 0);
      expect(groupEventPowerLevels[GruppechatEventTypes.background], 0);
      expect(groupEventPowerLevels.keys.toSet(), GruppechatEventTypes.all);
    });
  });
}
