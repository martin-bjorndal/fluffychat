// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:typed_data';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'giphy.dart';

/// Lets the person search Giphy, showing trending GIFs until they type,
/// and returns the GIF they tap.
Future<GiphyGif?> showGifPicker(BuildContext context, Client client) =>
    showModalBottomSheet<GiphyGif>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.85,
        child: GifPicker(giphy: Giphy(client)),
      ),
    );

class GifPicker extends StatefulWidget {
  final Giphy giphy;

  const GifPicker({required this.giphy, super.key});

  @override
  State<GifPicker> createState() => _GifPickerState();
}

class _GifPickerState extends State<GifPicker> {
  final _search = TextEditingController();
  Timer? _debounce;
  Future<List<GiphyGif>>? _gifs;

  /// Pictures already fetched, so scrolling back doesn't fetch them again.
  final Map<Uri, Future<Uint8List>> _pictures = {};

  String? get _language {
    final code = Localizations.localeOf(context).languageCode;
    // Giphy calls Norwegian "no"
    return code == 'nb' || code == 'nn' ? 'no' : code;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _gifs ??= widget.giphy.trending(language: _language);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// Searches once the person stops typing for a moment, which keeps within
  /// Giphy's limit on searches.
  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      final query = text.trim();
      setState(() {
        _gifs = query.isEmpty
            ? widget.giphy.trending(language: _language)
            : widget.giphy.search(query, language: _language);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _search,
            onChanged: _onChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_outlined),
              hintText: l10n.gruppechatSearchGifs,
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(32),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<GiphyGif>>(
            future: _gifs,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                Logs().w('GIF search failed', snapshot.error);
                return _Message(l10n.gruppechatGifsUnavailable);
              }
              final gifs = snapshot.data;
              if (gifs == null) {
                return const Center(
                  child: CircularProgressIndicator.adaptive(),
                );
              }
              if (gifs.isEmpty) return _Message(l10n.gruppechatNoGifsFound);
              return GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 140,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                ),
                itemCount: gifs.length,
                itemBuilder: (context, i) {
                  final gif = gifs[i];
                  return Material(
                    color: theme.colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(8),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => Navigator.of(context).pop(gif),
                      child: Tooltip(
                        message: gif.title,
                        child: FutureBuilder<Uint8List>(
                          future: _pictures[gif.preview] ??= widget.giphy
                              .download(gif.preview),
                          builder: (context, picture) {
                            final bytes = picture.data;
                            if (bytes == null) return const SizedBox.expand();
                            return Image.memory(
                              bytes,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        // Giphy's terms ask for this wherever their GIFs are searched
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'Powered by GIPHY',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  final String text;

  const _Message(this.text);

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(text, textAlign: TextAlign.center),
    ),
  );
}
