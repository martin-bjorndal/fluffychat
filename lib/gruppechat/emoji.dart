// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart'
    show CategoryEmoji, Emoji;
import 'package:emoji_picker_flutter/locales/default_emoji_set_locale.dart';
import 'package:flutter/widgets.dart';
import 'package:matrix/matrix.dart';

/// The emojis the app's emoji keyboards offer, for the app's [locale]: the
/// picker's own, with the newer ones it lacks, such as 🥲, each put in after
/// the emoji it belongs with. On Android the picker still leaves out what
/// the phone can't draw.
List<CategoryEmoji> gruppechatEmojiSet(Locale locale) =>
    _emojiSets[locale.languageCode] ??= _withMissingEmojis(
      getDefaultEmojiLocale(locale),
    );

final _emojiSets = <String, List<CategoryEmoji>>{};

List<CategoryEmoji> _withMissingEmojis(List<CategoryEmoji> set) {
  final categories = [
    for (final category in set)
      CategoryEmoji(category.category, [...category.emoji]),
  ];
  bool has(String emoji) =>
      categories.any((c) => c.emoji.any((e) => e.emoji == emoji));
  for (final (emoji, after) in addedKeyboardEmojis) {
    if (has(emoji.emoji)) continue;
    for (final category in categories) {
      final index = category.emoji.indexWhere((e) => e.emoji == after);
      if (index == -1) continue;
      category.emoji.insert(index + 1, emoji);
      break;
    }
  }
  return categories;
}

/// Emojis that emoji_picker_flutter's lists lack (Emoji 12.0 to 15.0), each
/// with the emoji it goes after.
const addedKeyboardEmojis = <(Emoji, String)>[
  // Faces
  (
    Emoji('🥲', 'face | happy | proud | relieved | smile | tear | touched'),
    '😙',
  ),
  (Emoji('😶‍🌫️', 'absentminded | clouds | face | fog | head'), '😶'),
  (Emoji('😮‍💨', 'blow | exhale | face | relief | sigh | whistle'), '😬'),
  (Emoji('🫨', 'earthquake | face | shaking | shock | vibrate'), '🤥'),
  (Emoji('🥸', 'disguise | face | glasses | incognito | nose'), '🥳'),
  (Emoji('🥱', 'bored | face | tired | yawn | yawning'), '😫'),
  // People and body
  (
    Emoji(
      '🫷',
      'hand | leftwards | push | refuse | stop | wait',
      hasSkinTone: true,
    ),
    '🫴',
  ),
  (
    Emoji(
      '🫸',
      'hand | push | refuse | rightwards | stop | wait',
      hasSkinTone: true,
    ),
    '🫷',
  ),
  (Emoji('🫀', 'anatomical | heart | organ | pulse'), '🧠'),
  (Emoji('🫁', 'breath | lungs | organ | respiration'), '🫀'),
  (
    Emoji('🥷', 'fighter | hidden | ninja | stealth', hasSkinTone: true),
    '💂‍♀️',
  ),
  (
    Emoji(
      '🫅',
      'crown | monarch | noble | person | royalty',
      hasSkinTone: true,
    ),
    '👷‍♀️',
  ),
  (
    Emoji('🫃', 'belly | bloated | full | man | pregnant', hasSkinTone: true),
    '🤰',
  ),
  (
    Emoji(
      '🫄',
      'belly | bloated | full | person | pregnant',
      hasSkinTone: true,
    ),
    '🫃',
  ),
  // Hearts
  (Emoji('❤️‍🩹', 'healing | heart | mending | recovering | well'), '❤️‍🔥'),
  (Emoji('🩷', 'cute | heart | like | love | pink'), '❤️'),
  (Emoji('🩵', 'cyan | heart | light blue | love | teal'), '💙'),
  (Emoji('🤎', 'brown | heart | love'), '💜'),
  (Emoji('🩶', 'gray | grey | heart | love | silver'), '🖤'),
  (Emoji('🤍', 'heart | love | white'), '🩶'),
  // Animals and nature
  (Emoji('🫎', 'animal | antlers | elk | moose'), '🐴'),
  (Emoji('🫏', 'animal | burro | donkey | mule | stubborn'), '🫎'),
  (Emoji('🦌', 'animal | deer | stag'), '🦄'),
  (Emoji('🦬', 'bison | buffalo | herd | wisent'), '🦌'),
  (Emoji('🦣', 'extinction | large | mammoth | tusk | woolly'), '🐘'),
  (Emoji('🦫', 'beaver | dam'), '🐿️'),
  (Emoji('🦤', 'dodo | extinction | large'), '🦉'),
  (Emoji('🪶', 'bird | feather | flight | light | plumage'), '🦤'),
  (Emoji('🪽', 'angelic | bird | flying | wing'), '🦜'),
  (Emoji('🐦‍⬛', 'bird | black | crow | raven'), '🪽'),
  (Emoji('🪿', 'bird | goose | honk | silly'), '🐦‍⬛'),
  (Emoji('🦭', 'sea lion | seal'), '🐬'),
  (Emoji('🪼', 'invertebrate | jelly | jellyfish | marine | sting'), '🪸'),
  (Emoji('🪲', 'beetle | bug | insect'), '🐝'),
  (Emoji('🪳', 'cockroach | insect | pest | roach'), '🦗'),
  (Emoji('🪰', 'fly | insect | maggot | pest'), '🦟'),
  (Emoji('🪱', 'earthworm | parasite | worm'), '🪰'),
  (Emoji('🪻', 'flower | hyacinth | lavender | lupine'), '🌷'),
  (Emoji('🪴', 'grow | house | plant | pot | potted'), '🌱'),
  // Food
  (Emoji('🫐', 'berry | bilberry | blue | blueberries | blueberry'), '🍓'),
  (Emoji('🫒', 'food | olive'), '🍅'),
  (Emoji('🫑', 'bell | capsicum | pepper | vegetable'), '🌶️'),
  (Emoji('🫚', 'ginger | root | spice'), '🌰'),
  (Emoji('🫛', 'beans | edamame | pea | pod | vegetable'), '🫚'),
  (Emoji('🫓', 'arepa | flatbread | lavash | naan | pita'), '🥖'),
  (Emoji('🫔', 'mexican | tamale | wrapped'), '🌯'),
  (Emoji('🫕', 'cheese | chocolate | fondue | melted | pot'), '🥘'),
  (Emoji('🫖', 'drink | pot | tea | teapot'), '☕'),
  (Emoji('🧋', 'boba | bubble | milk | pearl | tea'), '🥤'),
  // Places and travel
  (Emoji('🪨', 'boulder | heavy | rock | solid | stone'), '🧱'),
  (Emoji('🪵', 'log | lumber | timber | wood'), '🪨'),
  (Emoji('🛖', 'house | hut | roundhouse | yurt'), '🪵'),
  (Emoji('🚙', 'car | recreational | sport utility | suv'), '🚗'),
  (Emoji('🛻', 'pick-up | pickup | truck'), '🚙'),
  // Activities
  (Emoji('🪄', 'magic | magician | wand | witch | wizard'), '🔮'),
  (Emoji('🪅', 'celebration | party | piñata'), '🧸'),
  (Emoji('🪆', 'doll | matryoshka | nesting | russia'), '🪩'),
  (Emoji('🪡', 'embroidery | needle | sewing | stitches | tailoring'), '🧵'),
  (Emoji('🪢', 'knot | rope | tangled | tie | twine | twist'), '🧶'),
  // Objects
  (Emoji('🪭', 'fan | flamenco | flutter | folding | hot | shy'), '👚'),
  (Emoji('🪮', 'afro | comb | hair | pick'), '🪭'),
  (Emoji('🩴', 'beach | flip flop | sandal | thong'), '👢'),
  (Emoji('🪖', 'army | helmet | military | soldier'), '🧢'),
  (Emoji('🪗', 'accordion | concertina | squeeze box'), '🎷'),
  (Emoji('🪘', 'beat | conga | drum | long | rhythm'), '🥁'),
  (Emoji('🪇', 'instrument | maracas | music | percussion | shake'), '🪘'),
  (Emoji('🪈', 'fife | flute | music | pipe | recorder'), '🪇'),
  (Emoji('🪙', 'coin | gold | metal | money | silver | treasure'), '💰'),
  (Emoji('🪚', 'carpenter | lumber | saw | tool'), '🛡️'),
  (Emoji('🪛', 'screw | screwdriver | tool'), '🔧'),
  (Emoji('🪝', 'catch | crook | curve | hook'), '⛓️'),
  (Emoji('🪜', 'climb | ladder | rung | step'), '🧲'),
  (Emoji('🛗', 'accessibility | elevator | hoist | lift'), '🚪'),
  (Emoji('🪞', 'makeup | mirror | reflection'), '🛗'),
  (Emoji('🪟', 'frame | fresh air | opening | view | window'), '🪞'),
  (Emoji('🪠', 'plunger | suction | toilet'), '🚽'),
  (Emoji('🪤', 'bait | mouse | mousetrap | snare | trap'), '🛁'),
  (Emoji('🪣', 'bucket | cask | pail | vat'), '🧻'),
  (Emoji('🪥', 'bathroom | brush | clean | dental | teeth | toothbrush'), '🫧'),
  (Emoji('🪦', 'cemetery | grave | headstone | tombstone'), '⚰️'),
  (Emoji('🪧', 'card | notice | picket | placard | protest | sign'), '🗿'),
  // Symbols
  (Emoji('🛜', 'computer | internet | network | wifi | wireless'), '📶'),
  (Emoji('🪯', 'khanda | religion | sikh | sikhism'), '🔯'),
];

final _pictographic = RegExp(
  // The lint checks the pattern without the unicode flag, which \p{} needs
  // ignore: valid_regexps
  r'\p{Extended_Pictographic}|\p{Regional_Indicator}',
  unicode: true,
);

/// Most emojis a message can hold and still show big.
const maxBigEmojis = 6;

/// How many emojis [text] holds, as people see them, so skin tones, flags
/// and joined emojis such as 👨‍👩‍👧 count as one; null when it holds anything
/// but emojis and spaces.
int? emojiCount(String text) {
  final emojis = text.characters.where((c) => c.trim().isNotEmpty);
  if (emojis.isEmpty || !emojis.every(_pictographic.hasMatch)) return null;
  return emojis.length;
}

/// How much bigger than text [count] emojis alone are shown: smaller the
/// more there are, as in Messenger.
double bigEmojiScale(int count) => switch (count) {
  1 => 5,
  <= 3 => 3.5,
  _ => 2.5,
};

extension GruppechatEmojiEvent on Event {
  /// How many emojis this is, when it is a text message of only a few
  /// emojis, which the chat shows big and without a bubble.
  int? get bigEmojiCount {
    if (type != EventTypes.Message ||
        messageType != MessageTypes.Text ||
        redacted) {
      return null;
    }
    // "🎉 " is sent with the formatted text "🎉", as Markdown drops the space
    if (isRichMessage && formattedText.trim() != body.trim()) return null;
    final count = emojiCount(body);
    return count != null && count <= maxBigEmojis ? count : null;
  }
}
