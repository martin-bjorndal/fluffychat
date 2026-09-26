// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Pure Dart core of the Gruppechat features: roles, @role mentions,
// group-wide nicknames and shared backgrounds. Everything here works on plain
// state event content, so it can be unit tested without a Matrix client.
// `matrix_group.dart` connects it to real rooms.

/// Custom state event types, all stored in the group's space room.
abstract final class GruppechatEventTypes {
  static const String role = 'im.gruppechat.role';
  static const String memberRoles = 'im.gruppechat.member_roles';
  static const String nickname = 'im.gruppechat.nickname';
  static const String nicknameLock = 'im.gruppechat.nickname_lock';
  static const String background = 'im.gruppechat.background';

  static const Set<String> all = {
    role,
    memberRoles,
    nickname,
    nicknameLock,
    background,
  };
}

const String _userStateKeyPrefix = 'user:';

/// State key for data other people set about [userId].
///
/// Matrix only lets a user set a state key that starts with `@` when it is
/// their own user ID, so data about someone else needs a prefix.
String userStateKey(String userId) => '$_userStateKeyPrefix$userId';

/// The user ID in a [userStateKey], or null for any other key.
String? userIdFromStateKey(String stateKey) =>
    stateKey.startsWith(_userStateKeyPrefix)
    ? stateKey.substring(_userStateKeyPrefix.length)
    : null;

/// Read access to the state of one room.
abstract interface class GroupStateReader {
  Map<String, Object?>? content(String type, [String stateKey = '']);

  String? sender(String type, [String stateKey = '']);

  Iterable<String> stateKeys(String type);
}

/// Parses `#RRGGBB` or `#AARRGGBB` into an ARGB integer.
int? parseHexColor(Object? value) {
  if (value is! String) return null;
  var hex = value.trim();
  if (hex.startsWith('#')) hex = hex.substring(1);
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length != 8) return null;
  return int.tryParse(hex, radix: 16);
}

/// Formats an ARGB integer as `#RRGGBB`, or `#AARRGGBB` when not opaque.
String formatHexColor(int argb) {
  final alpha = (argb >> 24) & 0xFF;
  final hex = alpha == 0xFF
      ? (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')
      : (argb & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
  return '#${hex.toUpperCase()}';
}

double? _toDouble(Object? value) => value is num ? value.toDouble() : null;

class GroupRole {
  final String id;
  final String name;
  final int? color;
  final bool mentionable;

  const GroupRole({
    required this.id,
    required this.name,
    this.color,
    this.mentionable = true,
  });

  /// Returns null for a missing role or a deleted one (empty content).
  static GroupRole? fromContent(String id, Map<String, Object?>? content) {
    final name = content?['name'];
    if (name is! String || name.trim().isEmpty) return null;
    return GroupRole(
      id: id,
      name: name.trim(),
      color: parseHexColor(content?['color']),
      mentionable: content?['mentionable'] != false,
    );
  }

  Map<String, Object?> toContent() {
    final color = this.color;
    return {
      'name': name,
      if (color != null) 'color': formatHexColor(color),
      'mentionable': mentionable,
    };
  }
}

class GroupNickname {
  final String userId;
  final String name;
  final String? emoji;
  final String? setBy;

  const GroupNickname({
    required this.userId,
    required this.name,
    this.emoji,
    this.setBy,
  });

  String get displayName {
    final emoji = this.emoji;
    return emoji == null ? name : '$name $emoji';
  }

  static Map<String, Object?> contentFor(String name, {String? emoji}) => {
    'name': name.trim(),
    if (emoji != null && emoji.trim().isNotEmpty) 'emoji': emoji.trim(),
  };
}

enum GroupBackgroundKind { solid, gradient, image, none }

class GroupBackground {
  final GroupBackgroundKind kind;

  /// ARGB colors: one for [GroupBackgroundKind.solid], two or more for
  /// [GroupBackgroundKind.gradient].
  final List<int> colors;

  /// Gradient rotation in degrees.
  final double rotation;
  final double opacity;
  final double blur;

  /// `mxc://` URI of an image background.
  final Uri? url;

  const GroupBackground({
    required this.kind,
    this.colors = const [],
    this.rotation = 0,
    this.opacity = 1,
    this.blur = 0,
    this.url,
  });

  /// Returns null for missing, cleared (`{}`) or invalid content.
  static GroupBackground? fromContent(Map<String, Object?>? content) {
    if (content == null) return null;
    final kind = GroupBackgroundKind.values.asNameMap()[content['kind']];
    if (kind == null) return null;
    final rawColors = content['colors'];
    final url = content['url'];
    final background = GroupBackground(
      kind: kind,
      colors: rawColors is List
          ? rawColors.map(parseHexColor).whereType<int>().toList()
          : const [],
      rotation: _toDouble(content['rotation']) ?? 0,
      opacity: (_toDouble(content['opacity']) ?? 1).clamp(0, 1).toDouble(),
      blur: (_toDouble(content['blur']) ?? 0).clamp(0, 50).toDouble(),
      url: url is String ? Uri.tryParse(url) : null,
    );
    return background.isValid ? background : null;
  }

  bool get isValid => switch (kind) {
    GroupBackgroundKind.solid => colors.isNotEmpty,
    GroupBackgroundKind.gradient => colors.length >= 2,
    GroupBackgroundKind.image => url != null,
    GroupBackgroundKind.none => true,
  };

  Map<String, Object?> toContent() {
    final url = this.url;
    return {
      'kind': kind.name,
      if (colors.isNotEmpty) 'colors': colors.map(formatHexColor).toList(),
      if (kind == GroupBackgroundKind.gradient) 'rotation': rotation,
      'opacity': opacity,
      if (blur > 0) 'blur': blur,
      if (url != null) 'url': url.toString(),
    };
  }
}

/// Built-in backgrounds offered in the picker.
const List<(String, GroupBackground)> groupBackgroundPresets = [
  (
    'Midnight',
    GroupBackground(
      kind: GroupBackgroundKind.solid,
      colors: [0xFF1B1F3B],
      opacity: 0.6,
    ),
  ),
  (
    'Forest',
    GroupBackground(
      kind: GroupBackgroundKind.solid,
      colors: [0xFF1E3D2F],
      opacity: 0.6,
    ),
  ),
  (
    'Sand',
    GroupBackground(
      kind: GroupBackgroundKind.solid,
      colors: [0xFFE9DCC4],
      opacity: 0.6,
    ),
  ),
  (
    'Sunset',
    GroupBackground(
      kind: GroupBackgroundKind.gradient,
      colors: [0xFFFF6B6B, 0xFF556270],
      rotation: 135,
      opacity: 0.6,
    ),
  ),
  (
    'Aurora',
    GroupBackground(
      kind: GroupBackgroundKind.gradient,
      colors: [0xFF00C9A7, 0xFF845EC2],
      rotation: 160,
      opacity: 0.6,
    ),
  ),
  (
    'Fjord',
    GroupBackground(
      kind: GroupBackgroundKind.gradient,
      colors: [0xFF0F2027, 0xFF2C5364],
      rotation: 180,
      opacity: 0.6,
    ),
  ),
];

/// Picks the background to draw: a channel's own background overrides the
/// group's, and `none` anywhere means no shared background.
GroupBackground? resolveGroupBackground({
  GroupBackground? channel,
  GroupBackground? group,
  bool enabled = true,
}) {
  if (!enabled) return null;
  final chosen = channel ?? group;
  if (chosen == null || chosen.kind == GroupBackgroundKind.none) return null;
  return chosen;
}

/// Everything the group shares, read from the space room's state.
class GroupState {
  final GroupStateReader _reader;

  const GroupState(this._reader);

  /// Existing roles sorted by name. Deleted roles are left out.
  List<GroupRole> get roles =>
      _reader
          .stateKeys(GruppechatEventTypes.role)
          .map(roleById)
          .whereType<GroupRole>()
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  GroupRole? roleById(String id) => GroupRole.fromContent(
    id,
    _reader.content(GruppechatEventTypes.role, id),
  );

  /// The roles [userId] has, ignoring roles that were deleted.
  Set<String> roleIdsOf(String userId) {
    final raw = _reader.content(
      GruppechatEventTypes.memberRoles,
      userStateKey(userId),
    )?['roles'];
    if (raw is! List) return {};
    return raw.whereType<String>().where((id) => roleById(id) != null).toSet();
  }

  List<String> membersWithRole(String roleId) => _reader
      .stateKeys(GruppechatEventTypes.memberRoles)
      .map(userIdFromStateKey)
      .whereType<String>()
      .where((userId) => roleIdsOf(userId).contains(roleId))
      .toList();

  bool isNicknameLocked(String userId) =>
      _reader.content(GruppechatEventTypes.nicknameLock, userId)?['locked'] ==
      true;

  /// The group-wide nickname for [userId]. If the user has locked their
  /// nickname, only a nickname they set themselves counts.
  GroupNickname? nicknameOf(String userId) {
    final key = userStateKey(userId);
    final content = _reader.content(GruppechatEventTypes.nickname, key);
    final name = content?['name'];
    if (name is! String || name.trim().isEmpty) return null;
    final setBy = _reader.sender(GruppechatEventTypes.nickname, key);
    if (setBy != userId && isNicknameLocked(userId)) return null;
    final emoji = content?['emoji'];
    return GroupNickname(
      userId: userId,
      name: name.trim(),
      emoji: emoji is String && emoji.trim().isNotEmpty ? emoji.trim() : null,
      setBy: setBy,
    );
  }

  GroupBackground? get background =>
      GroupBackground.fromContent(_reader.content(GruppechatEventTypes.background));
}

RegExp _mentionPattern(String token) => RegExp(
  '(?<![A-Za-z0-9_@.:])@${RegExp.escape(token)}(?![A-Za-z0-9_:@-])',
  caseSensitive: false,
);

/// IDs of the mentionable roles that [text] mentions, as `@id` or `@Name`.
Set<String> mentionedRoleIds(String text, Iterable<GroupRole> roles) => {
  for (final role in roles)
    if (role.mentionable &&
        (_mentionPattern(role.id).hasMatch(text) ||
            _mentionPattern(role.name).hasMatch(text)))
      role.id,
};

/// Whether [text] mentions any of the roles in [ownRoleIds].
bool mentionsAnyRole(
  String text,
  Iterable<GroupRole> roles,
  Set<String> ownRoleIds,
) =>
    ownRoleIds.isNotEmpty &&
    mentionedRoleIds(
      text,
      roles.where((role) => ownRoleIds.contains(role.id)),
    ).isNotEmpty;

const Map<String, String> _transliterations = {
  'æ': 'ae',
  'ø': 'o',
  'å': 'a',
  'ä': 'a',
  'ö': 'o',
  'ü': 'u',
  'é': 'e',
};

/// A lowercase slug for a new role's ID, unique among [existingIds].
String roleIdFromName(String name, Iterable<String> existingIds) {
  var slug = name.trim().toLowerCase();
  for (final entry in _transliterations.entries) {
    slug = slug.replaceAll(entry.key, entry.value);
  }
  slug = slug
      .replaceAll(RegExp('[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final root = slug.isEmpty ? 'role' : slug;
  final taken = existingIds.toSet();
  var candidate = root;
  var suffix = 2;
  while (taken.contains(candidate)) {
    candidate = '$root-$suffix';
    suffix++;
  }
  return candidate;
}

/// Who may send each custom event type: moderators manage roles, everyone
/// can set nicknames and the background.
const Map<String, int> groupEventPowerLevels = {
  GruppechatEventTypes.role: 50,
  GruppechatEventTypes.memberRoles: 50,
  GruppechatEventTypes.nickname: 0,
  GruppechatEventTypes.nicknameLock: 0,
  GruppechatEventTypes.background: 0,
};

bool hasGroupPowerLevels(Map<String, Object?>? powerLevels) {
  final events = powerLevels?['events'];
  if (events is! Map) return false;
  return groupEventPowerLevels.keys.every(events.containsKey);
}

/// Adds the custom event types to power levels content. Values already set
/// in the room win, so admins can tighten or loosen them.
Map<String, Object?> withGroupPowerLevels(Map<String, Object?> powerLevels) {
  final events = powerLevels['events'];
  return {
    ...powerLevels,
    'events': <String, Object?>{
      ...groupEventPowerLevels,
      if (events is Map) ...events.cast<String, Object?>(),
    },
  };
}
