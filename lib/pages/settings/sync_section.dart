import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/services/service_locator.dart';
import 'package:i_zerak_app/services/sync/storage_access.dart';
import 'package:i_zerak_app/services/sync/sync_service.dart';

/// « il y a 3 min », partage par les reglages et le rail.
String syncAgo(AppLocalizations l10n, DateTime then, DateTime now) {
  final elapsed = now.difference(then);
  if (elapsed.inMinutes < 1) {
    return l10n.sync_ago_now;
  }
  if (elapsed.inHours < 1) {
    return l10n.sync_ago_minutes(elapsed.inMinutes);
  }
  if (elapsed.inDays < 1) {
    return l10n.sync_ago_hours(elapsed.inHours);
  }
  return l10n.sync_ago_days(elapsed.inDays);
}

/// La carte « Synchronisation » des reglages.
///
/// Elle vit a part du formulaire du Pi et s'applique d'elle-meme : le bouton
/// « Enregistrer » de la page ne concerne que le serveur, et un dossier mal
/// choisi doit pouvoir se corriger sans retoucher le reste.
class SyncSection extends StatefulWidget {
  SyncSection({
    super.key,
    SyncService? sync,
    StorageAccess? storage,
    this.clock,
  })  : sync = sync ?? getIt<SyncService>(),
        storage = storage ??
            (getIt.isRegistered<StorageAccess>() ? getIt<StorageAccess>() : const StorageAccess());

  final SyncService sync;
  final StorageAccess storage;
  final DateTime Function()? clock;

  @override
  State<SyncSection> createState() => _SyncSectionState();
}

class _SyncSectionState extends State<SyncSection> {
  final _folderController = TextEditingController();
  final _nameController = TextEditingController();
  late final AppLifecycleListener _lifecycle;

  /// `null` tant qu'on ne sait pas, ou quand la question ne se pose pas.
  bool? _storageGranted;
  bool _busy = false;

  bool get _desktop =>
      !kIsWeb &&
      const {TargetPlatform.windows, TargetPlatform.linux, TargetPlatform.macOS}
          .contains(defaultTargetPlatform);

  @override
  void initState() {
    super.initState();
    if (widget.sync.supported) {
      _folderController.text = widget.sync.folder ?? '';
      _nameController.text = widget.sync.deviceName;
    }
    // La permission s'accorde dans une page systeme : c'est au retour dans
    // l'application qu'il faut la relire.
    _lifecycle = AppLifecycleListener(onResume: _checkStorage);
    _checkStorage();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _folderController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _checkStorage() async {
    if (!widget.sync.supported || !widget.storage.isRequired) {
      return;
    }
    final granted = await widget.storage.isGranted();
    if (mounted) {
      setState(() => _storageGranted = granted);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _apply() => _run(() => widget.sync.configure(
        folder: _folderController.text.trim(),
        deviceName: _nameController.text.trim(),
      ));

  Future<void> _pickFolder() async {
    final path = await getDirectoryPath(initialDirectory: widget.sync.folder);
    if (path != null && mounted) {
      setState(() => _folderController.text = path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    final children = widget.sync.supported
        ? _fields(context, l10n, muted)
        : [Text(l10n.sync_unsupported, style: muted)];

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.sync, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(l10n.sync_section, style: theme.textTheme.titleMedium)),
            ]),
            const SizedBox(height: 4),
            Text(l10n.sync_section_hint, style: muted),
            const SizedBox(height: 16),
            for (var i = 0; i < children.length; i++) ...[
              children[i],
              if (i < children.length - 1) const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _fields(BuildContext context, AppLocalizations l10n, TextStyle? muted) => [
        if (_storageGranted == false) _storageWarning(context, l10n),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: TextField(
              controller: _folderController,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: l10n.sync_folder,
                hintText: _desktop ? r'C:\Users\…\Syncthing\iZerak' : '/storage/emulated/0/iZerak',
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          if (_desktop) ...[
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: OutlinedButton(onPressed: _pickFolder, child: Text(l10n.sync_pick_folder)),
            ),
          ],
        ]),
        TextField(
          controller: _nameController,
          decoration: InputDecoration(
            labelText: l10n.sync_device_name,
            border: const OutlineInputBorder(),
          ),
        ),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.tonal(
            onPressed: _busy ? null : _apply,
            child: Text(l10n.sync_apply),
          ),
          OutlinedButton.icon(
            onPressed: _busy || widget.sync.folder == null ? null : () => _run(widget.sync.syncNow),
            icon: const Icon(Icons.sync),
            label: Text(l10n.sync_now),
          ),
        ]),
        ValueListenableBuilder<SyncStatus>(
          valueListenable: widget.sync.status,
          builder: (context, status, _) => _statusView(context, l10n, status, muted),
        ),
      ];

  Widget _storageWarning(BuildContext context, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l10n.sync_storage_needed, style: TextStyle(color: scheme.onErrorContainer)),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: () async {
            await widget.storage.request();
            await _checkStorage();
          },
          child: Text(l10n.sync_storage_grant),
        ),
      ]),
    );
  }

  Widget _statusView(
    BuildContext context,
    AppLocalizations l10n,
    SyncStatus status,
    TextStyle? muted,
  ) {
    final now = (widget.clock ?? DateTime.now)();
    final scheme = Theme.of(context).colorScheme;
    final lines = <Widget>[
      if (status.phase == SyncPhase.disabled)
        Text(l10n.sync_disabled, style: muted)
      else if (status.phase == SyncPhase.syncing)
        Text(l10n.sync_rail_syncing, style: muted)
      else
        Text(
          status.lastSync == null
              ? l10n.sync_never
              : l10n.sync_last(syncAgo(l10n, status.lastSync!, now)),
          style: muted,
        ),
      if (status.error != null)
        Text(l10n.sync_error(status.error!), style: muted?.copyWith(color: scheme.error)),
      if (status.phase != SyncPhase.disabled) ...[
        if (status.peers.isEmpty)
          Text(l10n.sync_no_peer, style: muted)
        else
          for (final peer in status.peers)
            Row(children: [
              Icon(Icons.devices, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(l10n.sync_peer(peer.name, syncAgo(l10n, peer.writtenAt, now)),
                    style: muted),
              ),
            ]),
      ],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < lines.length; i++) ...[
          lines[i],
          if (i < lines.length - 1) const SizedBox(height: 4),
        ],
      ],
    );
  }
}
