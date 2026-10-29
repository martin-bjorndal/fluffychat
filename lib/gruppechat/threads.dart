// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

/// What the server reports about a thread alongside its first message: how
/// many replies it has, whether the current user took part, and the latest
/// reply.
class ThreadSummary {
  final int replyCount;
  final bool participated;

  /// The latest reply as the server sent it, still encrypted in encrypted
  /// chats.
  final MatrixEvent? latestReply;

  const ThreadSummary({
    this.replyCount = 0,
    this.participated = false,
    this.latestReply,
  });

  /// Reads the `m.thread` aggregation that the server bundles into the
  /// `unsigned` data of a thread's first message.
  factory ThreadSummary.fromUnsigned(Map<String, Object?>? unsigned) {
    final relations = unsigned?['m.relations'];
    if (relations is! Map<String, Object?>) return const ThreadSummary();
    final thread = relations[RelationshipTypes.thread];
    if (thread is! Map<String, Object?>) return const ThreadSummary();
    final count = thread['count'];
    final latest = thread['latest_event'];
    return ThreadSummary(
      replyCount: count is int && count > 0 ? count : 0,
      participated: thread['current_user_participated'] == true,
      latestReply: latest is Map<String, Object?> ? _parseEvent(latest) : null,
    );
  }
}

MatrixEvent? _parseEvent(Map<String, Object?> json) {
  try {
    return MatrixEvent.fromJson(json);
  } on Object catch (e) {
    Logs().w('Ignoring a malformed latest thread reply', e);
    return null;
  }
}

/// One thread in a chat: its first message and the latest reply, both
/// decrypted when the keys are available.
class GruppechatThread {
  final Event root;
  final ThreadSummary summary;
  final Event? latestReply;

  const GruppechatThread({
    required this.root,
    required this.summary,
    this.latestReply,
  });

  /// When anything last happened in the thread.
  DateTime get lastActivity =>
      latestReply?.originServerTs ?? root.originServerTs;
}

/// A page of a chat's threads, most recently active first.
class GruppechatThreadPage {
  final List<GruppechatThread> threads;

  /// Token for the next page, or null when there are no more threads.
  final String? nextBatch;

  const GruppechatThreadPage(this.threads, this.nextBatch);
}

extension GruppechatThreadsRoomExtension on Room {
  /// Loads one page of this chat's threads from the server, most recently
  /// active first. With [onlyMine], only threads the current user started or
  /// replied to are included. Pass the previous page's `nextBatch` as [from]
  /// to continue.
  Future<GruppechatThreadPage> loadGruppechatThreads({
    bool onlyMine = false,
    String? from,
    int limit = 20,
  }) async {
    final response = await client.getThreadRoots(
      id,
      include: onlyMine ? Include.participated : Include.all,
      limit: limit,
      from: from,
    );
    final threads = await Future.wait(
      response.chunk.map((matrixEvent) async {
        final summary = ThreadSummary.fromUnsigned(matrixEvent.unsigned);
        final latestReply = summary.latestReply;
        return GruppechatThread(
          root: await gruppechatDecrypt(matrixEvent),
          summary: summary,
          latestReply: latestReply == null
              ? null
              : await gruppechatDecrypt(latestReply),
        );
      }),
    );
    // Old messages can be from members whose names aren't loaded yet.
    final senderIds = <String>{
      for (final thread in threads) thread.root.senderId,
      ...threads.map((thread) => thread.latestReply?.senderId).nonNulls,
    };
    await Future.wait(
      senderIds
          .where((senderId) => senderId.isValidMatrixIdStrict())
          .map((senderId) => requestUser(senderId, ignoreErrors: true)),
    );
    return GruppechatThreadPage(threads, response.nextBatch);
  }

  /// [matrixEvent] as an event of this room, decrypted if it is encrypted and
  /// the keys are available.
  Future<Event> gruppechatDecrypt(MatrixEvent matrixEvent) async {
    final event = Event.fromMatrixEvent(matrixEvent, this);
    if (event.type != EventTypes.Encrypted || !client.encryptionEnabled) {
      return event;
    }
    try {
      return await client.encryption?.decryptRoomEvent(event) ?? event;
    } on Object catch (e, s) {
      Logs().w('Could not decrypt a thread message', e, s);
      return event;
    }
  }
}
