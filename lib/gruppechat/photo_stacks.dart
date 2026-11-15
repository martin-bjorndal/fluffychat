// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Photos sent together (a series, lib/gruppechat/file_series.dart) show in
// the chat as one stack: the first photo on top, the others lying under it
// and sticking out a little.

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/gruppechat/file_series.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// The photos of each stack in the chat, by the photo shown on top.
typedef PhotoStacks = Map<String, List<Event>>;

/// What finds a stack again from the photo on top, also when its message
/// has been changed (the changed photo is another [Event]).
String? _stackKey(Event event) {
  final series = event.fileSeries;
  if (series == null) return null;
  return '${event.senderId}|${series.id}|${series.index}';
}

// A photo still sending, or failed, stays on its own, with its own retry.
bool _stackable(Event event) =>
    event.type == EventTypes.Message &&
    event.messageType == MessageTypes.Image &&
    !event.redacted &&
    event.status.isSent &&
    event.fileSeries != null;

/// [events] as the chat shows them (newest first), with each run of photos
/// from one series made into one item: its first photo, which carries the
/// message, in the place of the run. The photos of each stack, in the order
/// they were sent, go into [stacks].
///
/// A run is photos one after the other from the same sender in the same
/// series; any other message in between ends it, so nothing moves out of
/// time order, and the rest of the series makes a stack of its own.
///
/// The stack is found again from the first photo as shown, after any change
/// to its message ([timeline]); a change made in another app may have
/// dropped the series, and then the photos stay one by one.
List<Event> stackPhotoSeries(
  List<Event> events,
  PhotoStacks stacks, {
  Timeline? timeline,
}) {
  final shown = <Event>[];
  var i = 0;
  while (i < events.length) {
    final event = events[i];
    var end = i + 1;
    if (_stackable(event)) {
      final id = event.fileSeries!.id;
      while (end < events.length &&
          _stackable(events[end]) &&
          events[end].senderId == event.senderId &&
          events[end].fileSeries!.id == id) {
        end++;
      }
    }
    final photos = events.sublist(i, end)
      ..sort((a, b) => a.fileSeries!.index.compareTo(b.fileSeries!.index));
    final key = photos.length < 2
        ? null
        : _stackKey(
            timeline == null
                ? photos.first
                : photos.first.getDisplayEvent(timeline),
          );
    if (key == null) {
      shown.addAll(events.sublist(i, end));
    } else {
      shown.add(photos.first);
      // Found from the photo as shown and as it came
      stacks[key] = photos;
      stacks[_stackKey(photos.first)!] = photos;
    }
    i = end;
  }
  return shown;
}

/// Where the message [eventId] is in the chat's list made from [events]
/// with [stackPhotoSeries]: a photo under another is where its stack is.
/// -1 when it isn't there.
int stackedIndexOf(List<Event> events, String eventId, {Timeline? timeline}) {
  final stacks = <String, List<Event>>{};
  final shown = stackPhotoSeries(events, stacks, timeline: timeline);
  return shown.indexWhere((event) => isInItem(stacks, event, eventId));
}

/// Whether the message [eventId] is the chat's item [event], or one of the
/// photos of the stack it tops: what a read marker or a jump on it shows on.
bool isInItem(PhotoStacks stacks, Event event, String? eventId) =>
    event.eventId == eventId ||
    GruppechatPhotoStacks.photosOf(
      stacks,
      event,
    ).any((photo) => photo.eventId == eventId);

/// Gives the chat's stacks to the messages in it.
class GruppechatPhotoStacks extends InheritedWidget {
  final PhotoStacks stacks;

  const GruppechatPhotoStacks({
    required this.stacks,
    required super.child,
    super.key,
  });

  /// The photos of the stack [event] is on top of, in the order they were
  /// sent; empty when it isn't on top of one.
  static List<Event> of(BuildContext context, Event event) {
    final stacks = context
        .dependOnInheritedWidgetOfExactType<GruppechatPhotoStacks>()
        ?.stacks;
    return stacks == null ? const [] : photosOf(stacks, event);
  }

  /// The photos of the stack in [stacks] that [event] is on top of.
  static List<Event> photosOf(PhotoStacks stacks, Event event) {
    final key = _stackKey(event);
    return key == null ? const [] : stacks[key] ?? const [];
  }

  // Made anew with the list, which builds its messages anew anyway
  @override
  bool updateShouldNotify(GruppechatPhotoStacks oldWidget) => true;
}

/// The photo on top ([child]) with the next ones of [photos] lying under it,
/// their edges sticking out above and to the right, and how many there are.
class GruppechatPhotoStack extends StatelessWidget {
  final List<Event> photos;
  final double width;
  final double height;
  final Widget child;

  static const step = 6.0;

  const GruppechatPhotoStack({
    required this.photos,
    required this.width,
    required this.height,
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final under = photos.skip(1).take(2).toList();
    final shift = step * under.length;
    final radius = BorderRadius.circular(AppConfig.borderRadius);
    return Stack(
      children: [
        // The lowest first, so the next photo lies over it
        for (final (i, photo) in under.indexed.toList().reversed)
          Positioned(
            left: step * (i + 1),
            top: shift - step * (i + 1),
            width: width,
            height: height,
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: theme.dividerColor),
              ),
              child: ClipRRect(
                borderRadius: radius,
                child: ColoredBox(
                  color: theme.colorScheme.surfaceContainerHigh,
                  child: MxcImage(
                    cacheKey: photo.transactionId ?? photo.eventId,
                    cacheName: photo.room.id,
                    event: photo,
                    width: width,
                    height: height,
                    fit: BoxFit.cover,
                    isThumbnail: true,
                  ),
                ),
              ),
            ),
          ),
        Padding(
          padding: EdgeInsets.only(top: shift, right: shift),
          child: child,
        ),
        Positioned(
          top: shift + 8,
          right: shift + 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 4,
              children: [
                const Icon(
                  Icons.photo_library_outlined,
                  size: 14,
                  color: Colors.white,
                ),
                Text(
                  '${photos.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
