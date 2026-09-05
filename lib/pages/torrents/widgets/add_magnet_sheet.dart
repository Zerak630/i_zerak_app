import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/media_match_dao.dart';
import 'package:i_zerak_app/models/server_config_dao.dart';
import 'package:i_zerak_app/services/tmdb/tmdb_service.dart';

/// Ce que la feuille renvoie a la page appelante.
typedef MagnetRequest = ({String magnet, String? savePath, String? category});

/// Reconnait un lien magnet ou une URL de fichier torrent.
final RegExp magnetPattern = RegExp(
  r'^(magnet:\?xt=urn:btih:[a-zA-Z0-9]+.*|https?://\S+\.torrent(\?\S*)?)$',
  caseSensitive: false,
);

Future<MagnetRequest?> showAddMagnetSheet(
  BuildContext context, {
  required ServerConfig config,
  required TmdbService tmdb,
}) =>
    showModalBottomSheet<MagnetRequest>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        // Laisse la place au clavier, sans quoi les champs du bas sont masques.
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _AddMagnetSheet(config: config, tmdb: tmdb),
      ),
    );

class _AddMagnetSheet extends StatefulWidget {
  const _AddMagnetSheet({required this.config, required this.tmdb});

  final ServerConfig config;
  final TmdbService tmdb;

  @override
  State<_AddMagnetSheet> createState() => _AddMagnetSheetState();
}

class _AddMagnetSheetState extends State<_AddMagnetSheet> {
  final _formKey = GlobalKey<FormState>();
  final _magnetController = TextEditingController();
  final _searchController = TextEditingController();
  final _folderController = TextEditingController();
  final _imdbController = TextEditingController();

  Timer? _debounce;
  List<MediaMatch> _results = const [];
  MediaMatch? _selected;
  bool _searching = false;
  String? _searchError;

  @override
  void initState() {
    super.initState();
    _prefillFromClipboard();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _magnetController.dispose();
    _searchController.dispose();
    _folderController.dispose();
    _imdbController.dispose();
    super.dispose();
  }

  /// Lu une seule fois a l'ouverture : sur iOS 16 et suivants, chaque lecture du
  /// presse-papier affiche un bandeau systeme.
  Future<void> _prefillFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (!mounted || text == null || !magnetPattern.hasMatch(text)) {
      return;
    }
    _magnetController.text = text;
  }

  void _onSearchChanged(String value) {
    // Sans anti-rebond, chaque frappe declencherait une requete TMDB.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(value));
  }

  Future<void> _search(String query) async {
    if (query.trim().length < 2) {
      setState(() {
        _results = const [];
        _searchError = null;
      });
      return;
    }

    setState(() {
      _searching = true;
      _searchError = null;
    });

    try {
      final results = await widget.tmdb.search(query);
      if (!mounted) {
        return;
      }
      setState(() {
        _results = results;
        _searching = false;
      });
    } on TmdbException catch (error) {
      if (!mounted) {
        return;
      }
      // Une panne TMDB ne doit pas bloquer l'ajout : le champ IMDb libre et le
      // nom de dossier restent modifiables a la main.
      setState(() {
        _searching = false;
        _results = const [];
        _searchError = switch (error) {
          TmdbNotConfiguredException() => AppLocalizations.of(context)!.tmdb_not_configured,
          TmdbAuthException() => AppLocalizations.of(context)!.tmdb_auth_error,
          TmdbNetworkException() => AppLocalizations.of(context)!.tmdb_unreachable,
        };
      });
    }
  }

  Future<void> _select(MediaMatch match) async {
    setState(() {
      _selected = match;
      _results = const [];
      _searchController.text = match.title;
      _folderController.text = match.embyFolderName();
    });

    try {
      final enriched = await widget.tmdb.withImdbId(match);
      if (!mounted) {
        return;
      }
      setState(() {
        _selected = enriched;
        _imdbController.text = enriched.imdbId ?? '';
        _folderController.text = enriched.embyFolderName();
      });
    } on TmdbException catch (_) {
      // Le titre et l'annee suffisent a Emby dans la majorite des cas ;
      // l'identifiant reste saisissable a la main.
    }
  }

  /// Applique un identifiant IMDb saisi manuellement, en acceptant aussi bien
  /// une URL complete qu'un identifiant nu.
  void _applyManualImdb(String raw) {
    final id = extractImdbId(raw);
    final selected = _selected;
    if (id == null || selected == null) {
      return;
    }
    setState(() {
      _selected = selected.copyWith(imdbId: id);
      _folderController.text = _selected!.embyFolderName();
    });
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final root = widget.config.defaultSavePath?.trim();
    final folder = _folderController.text.trim();

    String? savePath;
    if (root != null && root.isNotEmpty) {
      savePath = folder.isEmpty ? root : '${root.replaceAll(RegExp(r'/+$'), '')}/$folder';
    }

    Navigator.pop(context, (
      magnet: _magnetController.text.trim(),
      savePath: savePath,
      category: _categoryForSelection(),
    ));
  }

  String? _categoryForSelection() {
    final configured = widget.config.defaultCategory?.trim();
    if (configured != null && configured.isNotEmpty) {
      return configured;
    }
    return switch (_selected?.kind) {
      MediaKind.movie => 'movies',
      MediaKind.tv => 'series',
      null => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.add_magnet,
                  style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              TextFormField(
                controller: _magnetController,
                maxLines: 2,
                minLines: 1,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: l10n.magnet_link,
                  hintText: 'magnet:?xt=urn:btih:...',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.content_paste),
                    tooltip: l10n.paste,
                    onPressed: () async {
                      final data = await Clipboard.getData(Clipboard.kTextPlain);
                      final text = data?.text?.trim();
                      if (text != null && text.isNotEmpty) {
                        _magnetController.text = text;
                      }
                    },
                  ),
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) {
                    return l10n.please_enter_a_magnet;
                  }
                  return magnetPattern.hasMatch(text) ? null : l10n.please_enter_a_valid_magnet;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  labelText: l10n.search_title,
                  helperText: l10n.search_title_hint,
                  border: const OutlineInputBorder(),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(12.0),
                          child: SizedBox(
                              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : const Icon(Icons.search),
                ),
              ),
              if (_searchError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(_searchError!,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Theme.of(context).colorScheme.error)),
                ),
              if (_results.isNotEmpty) _resultsStrip(context),
              if (_selected != null) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _imdbController,
                  autocorrect: false,
                  onChanged: _applyManualImdb,
                  decoration: InputDecoration(
                    labelText: l10n.imdb_id,
                    hintText: 'tt1234567',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                controller: _folderController,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: l10n.emby_folder,
                  helperText: l10n.emby_folder_hint,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                      onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
                  FilledButton(onPressed: _submit, child: Text(l10n.add)),
                ],
              ),
              const SizedBox(height: 8),
              Text(l10n.tmdb_attribution,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resultsStrip(BuildContext context) => SizedBox(
        height: 190,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          itemCount: _results.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            final match = _results[index];
            return InkWell(
              onTap: () => _select(match),
              child: SizedBox(
                width: 92,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (match.posterPath != null)
                      Image.network(
                        '${TmdbService.imageBaseUrl}${match.posterPath}',
                        width: 92,
                        height: 138,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox(
                            width: 92, height: 138, child: Icon(Icons.movie)),
                      )
                    else
                      const SizedBox(width: 92, height: 138, child: Icon(Icons.movie)),
                    const SizedBox(height: 4),
                    Text(
                      match.year == null ? match.title : '${match.title} (${match.year})',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
}
