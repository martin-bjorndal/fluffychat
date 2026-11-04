// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// The throwaway server that tests/testserver starts, and test accounts that
// log in to it with the Matrix SDK set up as in the app
// (lib/utils/client_manager.dart), end-to-end encryption included.
// `python tests/run.py e2e` in the parent repository starts the server and
// runs these tests; without it they are skipped.

import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:fluffychat/gruppechat/invite_codes.dart';
import 'package:fluffychat/gruppechat/matrix_group.dart';
import 'package:fluffychat/gruppechat/sign_up.dart';
import 'package:fluffychat/utils/matrix_live_kit_calls/matrix_live_kit_call_member.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:matrix/encryption/utils/key_verification.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// One of the accounts the test server registers: alice (a server admin),
/// bob and carol.
class TestAccount {
  final String name;
  final String userId;
  final String password;
  final bool admin;

  const TestAccount(this.name, this.userId, this.password, this.admin);
}

class TestServer {
  /// Where the app would connect: Caddy with the server's Caddyfile, or
  /// Synapse itself when the test server runs without Caddy.
  final Uri homeserver;
  final Uri synapse;
  final bool behindCaddy;

  /// Caddy's test certificate authority, which [homeserver] needs.
  final String? rootCertificate;
  final String serverName;

  /// The stand-ins for the push gateway and Giphy (tests/testserver/
  /// fake_services.py).
  final Uri fakeServices;

  /// What pushers send to: Caddy's push route, as on the server.
  final Uri pushGateway;
  final String giphyApiKey;
  final Map<String, Object?> webVersion;
  final Map<String, TestAccount> accounts;

  const TestServer._({
    required this.homeserver,
    required this.synapse,
    required this.behindCaddy,
    required this.rootCertificate,
    required this.serverName,
    required this.fakeServices,
    required this.pushGateway,
    required this.giphyApiKey,
    required this.webVersion,
    required this.accounts,
  });

  /// The server named by GRUPPECHAT_TEST_SERVER, or null when there is none.
  static final TestServer? instance = _load();

  static TestServer? _load() {
    final path = Platform.environment['GRUPPECHAT_TEST_SERVER'];
    if (path == null || path.isEmpty) return null;
    final json =
        jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
    final accounts = json['accounts'] as Map<String, Object?>;
    return TestServer._(
      homeserver: Uri.parse(json['homeserver'] as String),
      synapse: Uri.parse(json['synapse'] as String),
      behindCaddy: json['caddy'] != null,
      rootCertificate: json['root_certificate'] as String?,
      serverName: json['server_name'] as String,
      fakeServices: Uri.parse(json['fake_services'] as String),
      pushGateway: Uri.parse(json['push_gateway'] as String),
      giphyApiKey: json['giphy_api_key'] as String,
      webVersion: json['web_version'] as Map<String, Object?>,
      accounts: {
        for (final MapEntry(:key, :value) in accounts.entries)
          key: TestAccount(
            key,
            (value as Map<String, Object?>)['user_id'] as String,
            value['password'] as String,
            value['admin'] as bool,
          ),
      },
    );
  }

  TestAccount account(String name) =>
      accounts[name] ?? (throw ArgumentError('No test account $name'));

  /// An HTTP client that trusts the test server's certificate.
  http.Client httpClient() {
    final certificate = rootCertificate;
    if (certificate == null) return http.Client();
    final context = SecurityContext(withTrustedRoots: true)
      ..setTrustedCertificates(certificate);
    return IOClient(HttpClient(context: context));
  }

  /// What the stand-in services recorded: `pushes` or `giphy`.
  Future<List<Map<String, Object?>>> recorded(String what) async {
    final response = await http.get(fakeServices.resolve('/_test/$what'));
    return (jsonDecode(response.body) as List).cast<Map<String, Object?>>();
  }

  Future<void> forget(String what) =>
      http.delete(fakeServices.resolve('/_test/$what'));
}

/// The reason to skip the end-to-end tests, or null when the server runs.
final Object? skipWithoutTestServer = TestServer.instance == null
    ? 'Needs the test server: python tests/run.py e2e'
    : null;

TestServer get testServer => TestServer.instance!;

bool _encryptionReady = false;

/// Loads vodozemac, the end-to-end encryption library, which the app gets
/// from flutter_vodozemac. tests/run.py builds it for this computer and
/// passes its folder in GRUPPECHAT_VODOZEMAC.
Future<void> _initEncryption() async {
  if (_encryptionReady) return;
  final folder = Platform.environment['GRUPPECHAT_VODOZEMAC'];
  if (folder == null || folder.isEmpty) {
    throw StateError(
      'GRUPPECHAT_VODOZEMAC is not set: run the tests with tests/run.py',
    );
  }
  // The loader takes a URI, which a Windows path isn't
  await vod.init(libraryPath: Uri.directory(folder).toString());
  _encryptionReady = true;
}

final _clients = <Client>[];
var _clientCount = 0;
Directory? _databases;

/// Logs [name] in on a new device, set up like the app's own client. Give
/// the [password] for accounts the tests made themselves.
Future<Client> logIn(String name, {String? password}) async {
  final client = await newClient(name);
  await client.login(
    LoginType.mLoginPassword,
    identifier: AuthenticationUserIdentifier(user: name),
    password: password ?? testServer.account(name).password,
    initialDeviceDisplayName: 'e2e $name',
  );
  if (!client.encryptionEnabled) {
    throw StateError('End-to-end encryption did not start for $name');
  }
  return client;
}

/// A client set up like the app's own (lib/utils/client_manager.dart),
/// connected to the test server but not logged in yet.
Future<Client> newClient(String name) async {
  await _initEncryption();
  final number = ++_clientCount;
  final databases = _databases ??= Directory.systemTemp.createTempSync(
    'gruppechat-e2e',
  );
  final client = Client(
    'gruppechat-e2e-$name-$number',
    httpClient: testServer.httpClient(),
    verificationMethods: {
      KeyVerificationMethod.numbers,
      KeyVerificationMethod.emoji,
    },
    importantStateEvents: {
      'im.ponies.room_emotes',
      MatrixRtcCallMember.eventType,
      ...gruppechatImportantStateEvents,
    },
    database: await MatrixSdkDatabase.init(
      'e2e-$name-$number',
      database: await databaseFactoryFfi.openDatabase(
        '${databases.path}/$name-$number.sqlite',
      ),
      sqfliteFactory: databaseFactoryFfi,
    ),
    supportedLoginTypes: {
      AuthenticationTypes.password,
      AuthenticationTypes.sso,
    },
    enableDehydratedDevices: true,
    shareKeysWith: ShareKeysWith.all,
  );
  _clients.add(client);
  await client.checkHomeserver(testServer.homeserver);
  return client;
}

var _signUps = 0;

/// A new account, signed up with an invite code from [admin] the way the
/// app's sign-up page does it (lib/gruppechat/sign_up.dart), for tests that
/// change an account in ways the shared accounts shouldn't keep.
Future<(Client, String)> signUpNewAccount(Client admin, String name) async {
  final code = await admin.createInviteCode();
  final client = await newClient(name);
  final username = '$name${DateTime.now().millisecondsSinceEpoch}${++_signUps}';
  final password = 'password-$username';
  await signUpWithInviteCode(
    client,
    username: username,
    password: password,
    inviteCode: code.code,
    deviceName: 'e2e $name',
  );
  return (client, password);
}

/// Logs out every client [logIn] made, so their devices don't pile up on the
/// accounts. Use it in `tearDownAll`.
Future<void> logOutEveryone() async {
  for (final client in _clients) {
    try {
      if (client.isLogged()) await client.logout();
    } catch (e) {
      Logs().w('Could not log out ${client.clientName}', e);
    }
    await client.dispose(closeDatabase: true);
  }
  _clients.clear();
}

/// Waits until [condition] holds, checking as the clients sync.
Future<void> eventually(
  String what,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  await valueOf(what, () => condition() ? true : null, timeout: timeout);
}

/// Waits until [find] returns something, and returns it.
Future<T> valueOf<T extends Object>(
  String what,
  T? Function() find, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (true) {
    final value = find();
    if (value != null) return value;
    if (DateTime.now().isAfter(end)) {
      throw TestFailure('Timed out after ${timeout.inSeconds}s: $what');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

/// [client]'s view of [roomId] once it has joined it.
Future<Room> joined(Client client, String roomId) => valueOf(
  '${client.userID} has joined $roomId',
  () => client.getRoomById(roomId)?.membership == Membership.join
      ? client.getRoomById(roomId)
      : null,
);

/// Accepts the invite to [roomId] once it reaches [client].
Future<Room> accept(Client client, String roomId) async {
  final room = await valueOf(
    '${client.userID} is invited to $roomId',
    () => client.getRoomById(roomId),
  );
  if (room.membership != Membership.join) await room.join();
  return joined(client, roomId);
}

/// Waits until [room]'s members, as [room]'s client sees them, include
/// [userIds], so that what it encrypts next reaches them. Asks the server,
/// as the SDK does before encrypting, since a room's members aren't always
/// all in memory.
Future<void> seesMembers(Room room, Iterable<String> userIds) async {
  final wanted = userIds.toSet();
  final end = DateTime.now().add(const Duration(seconds: 30));
  while (true) {
    final members = await room.requestParticipants([Membership.join], true);
    if (members.map((user) => user.id).toSet().containsAll(wanted)) break;
    if (DateTime.now().isAfter(end)) {
      throw TestFailure(
        'Timed out: ${room.client.userID} sees $wanted in ${room.id}',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  await room.client.updateUserDeviceKeys(additionalUsers: wanted);
}

/// An encrypted direct chat that [from] starts with [to], as the app does
/// from someone's profile, once both are in it.
Future<(Room, Room)> directChat(Client from, Client to) async {
  final roomId = await from.startDirectChat(to.userID!);
  final theirs = await accept(to, roomId);
  final mine = await joined(from, roomId);
  await seesMembers(mine, [to.userID!]);
  await seesMembers(theirs, [from.userID!]);
  return (mine, theirs);
}

/// The first event in [timeline] that matches [where], once it arrives.
Future<Event> arrives(
  Timeline timeline,
  String what,
  bool Function(Event event) where, {
  Duration timeout = const Duration(seconds: 30),
}) => valueOf(
  '${timeline.room.client.userID} receives $what',
  () => timeline.events.firstWhereOrNull(where),
  timeout: timeout,
);

/// The first event in [timeline] that matches [where], loading older
/// messages from the server until it turns up.
Future<Event> inHistory(
  Timeline timeline,
  String what,
  bool Function(Event event) where, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (true) {
    final found = timeline.events.firstWhereOrNull(where);
    if (found != null) return found;
    if (DateTime.now().isAfter(end)) {
      throw TestFailure('Timed out after ${timeout.inSeconds}s: $what');
    }
    if (timeline.canRequestHistory) {
      await timeline.requestHistory();
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}

/// A group made by [newGroup]: its space and channels, by name.
class TestGroup {
  final String spaceId;
  final Map<String, String> channels;

  const TestGroup(this.spaceId, this.channels);

  String get firstChannel => channels.values.first;
}

/// A group that [owner] makes with [members], as the app does
/// (lib/pages/new_group/new_group.dart): a space, and each of [channels] an
/// encrypted group chat in it. Everyone joins everything, and unless
/// [setUp] is false, the owner sets up group features as the app does when
/// it opens the group.
Future<TestGroup> newGroup(
  Client owner,
  List<Client> members, {
  String name = 'Testgruppe',
  List<String> channels = const ['general'],
  bool setUp = true,
}) async {
  final spaceId = await owner.createRoom(
    preset: CreateRoomPreset.privateChat,
    creationContent: {'type': RoomCreationTypes.mSpace},
    name: name,
    powerLevelContentOverride: {'events_default': 100},
  );
  final space = await joined(owner, spaceId);
  final channelIds = <String, String>{};
  for (final channel in channels) {
    final roomId = await owner.createGroupChat(
      visibility: Visibility.private,
      preset: CreateRoomPreset.privateChat,
      groupName: channel,
      powerLevelContentOverride: {
        'events': {MatrixRtcCallMember.eventType: 0},
      },
      initialState: [],
    );
    await space.setSpaceChild(roomId);
    channelIds[channel] = roomId;
  }
  final roomIds = [spaceId, ...channelIds.values];
  for (final member in members) {
    for (final roomId in roomIds) {
      await owner.getRoomById(roomId)!.invite(member.userID!);
    }
  }
  for (final member in members) {
    for (final roomId in roomIds) {
      await accept(member, roomId);
    }
  }
  final everyone = [owner, ...members];
  for (final client in everyone) {
    for (final roomId in channelIds.values) {
      await seesMembers(
        client.getRoomById(roomId)!,
        everyone.map((c) => c.userID!),
      );
      await eventually(
        '${client.userID} sees $roomId in the group',
        () =>
            GruppechatGroup.of(client.getRoomById(roomId)!)?.space.id ==
            spaceId,
      );
    }
  }
  if (setUp) {
    await GruppechatGroup(space).setUp();
    for (final client in everyone) {
      await eventually(
        '${client.userID} sees the group set up',
        () => !GruppechatGroup(client.getRoomById(spaceId)!).needsSetup,
      );
    }
  }
  return TestGroup(spaceId, channelIds);
}

/// Whether [action] is refused by the server as not allowed.
Future<bool> isForbidden(Future<void> Function() action) async {
  try {
    await action();
    return false;
  } on MatrixException catch (e) {
    return e.errcode == 'M_FORBIDDEN';
  }
}

/// Waits until [find], asked again every half second, returns something,
/// and returns it. For what has to be fetched from the server each time.
Future<T> fetchedValue<T extends Object>(
  String what,
  Future<T?> Function() find, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (true) {
    final value = await find();
    if (value != null) return value;
    if (DateTime.now().isAfter(end)) {
      throw TestFailure('Timed out after ${timeout.inSeconds}s: $what');
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
}

/// A message's text as the chat shows it: without the quote of the message
/// it replies to, which the SDK puts in front for older apps.
String textOf(Event event) => event.calcLocalizedBodyFallback(
  const MatrixDefaultLocalizations(),
  hideReply: true,
);
