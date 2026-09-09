import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/media_match_dao.dart';
import 'package:i_zerak_app/models/server_config_dao.dart';
import 'package:i_zerak_app/models/torrent_destination.dart';
import 'package:i_zerak_app/services/tmdb/tmdb_service.dart';

/// Ce que la feuille renvoie a la page appelante.
///
/// `destination` sert uniquement au message de confirmation ; tout le rangement
/// est deja resolu dans `options`.
typedef MagnetRequest = ({
  String magnet,
  TorrentDestination destination,
  AddTorrentOptions options,
});

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

  Timer? _debounce;
  List<MediaMatch> _results = const [];
  MediaMatch? _selected;
  bool _searching = false;
  String? _searchError;

  /// Choix explicite de l'utilisateur, qui l'emporte sur la deduction TMDB.
  ///
  /// Il est **collant** : selectionner un autre titre ensuite ne le remet pas a
  /// zero. Le bouton segmente reste visible en permanence, l'etat est donc
  /// lisible a tout moment, et un basculement automatique apres un choix
  /// delibere serait une surprise silencieuse.
  TorrentDestination? _destinationOverride;

  TorrentDestination get _destination =>
      _destinationOverride ?? TorrentDestination.fromKind(_selected?.kind);

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

  /// Synchrone : l'identifiant TMDB figure deja dans le resultat de recherche,
  /// il n'y a plus d'aller-retour reseau pour completer le nom de dossier.
  void _select(MediaMatch match) {
    setState(() {
      _selected = match;
      _results = const [];
      _searchController.text = match.title;
      _folderController.text = match.embyFolderName();
    });
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final destination = _destination;
    Navigator.pop(context, (
      magnet: _magnetController.text.trim(),
      destination: destination,
      options: resolveAddOptions(
        destination: destination,
        basePath: destinationPath(
          libraryRoot: widget.config.defaultSavePath,
          destination: destination,
        ),
        folderName: _folderController.text.trim(),
      ),
    ));
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
              const SizedBox(height: 16),
              _destinationPicker(context, l10n),
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

  /// Bouton segmente a trois valeurs, toujours visible.
  ///
  /// Pas d'icones : trois segments portant a la fois une icone et un libelle
  /// debordent sur un ecran de 320 dp, et le libelle seul suffit.
  Widget _destinationPicker(BuildContext context, AppLocalizations l10n) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<TorrentDestination>(
            segments: [
              ButtonSegment(
                  value: TorrentDestination.films, label: Text(l10n.destination_movies)),
              ButtonSegment(
                  value: TorrentDestination.series, label: Text(l10n.destination_series)),
              ButtonSegment(
                  value: TorrentDestination.autres, label: Text(l10n.destination_other)),
            ],
            selected: {_destination},
            showSelectedIcon: false,
            onSelectionChanged: (values) =>
                setState(() => _destinationOverride = values.first),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(
              l10n.destination_hint,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      );

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
