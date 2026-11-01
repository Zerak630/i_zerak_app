import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/screen_time_dao.dart';

/// Une duree en minutes, comme on la dit : « 38 min », « 1 h 05 ».
String formatMinutes(AppLocalizations l10n, double minutes) {
  final total = minutes.round();
  if (total < 60) {
    return l10n.free_minutes(total);
  }
  return l10n.free_hours(total ~/ 60, (total % 60).toString().padLeft(2, '0'));
}

/// Une heure de la journee : « 22 h » en francais, « 10 pm » en anglais.
String formatHour(BuildContext context, int hour) =>
    MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay(hour: hour, minute: 0),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );

/// Choix des applications suivies. Renvoie la nouvelle liste, ou `null` si
/// rien ne change.
///
/// Les applications deja suivies mais desinstallees depuis restent dans la
/// liste : les decocher doit rester possible.
class AppPickerPage extends StatefulWidget {
  const AppPickerPage({super.key, required this.available, required this.selected});

  final List<TrackedApp> available;
  final List<TrackedApp> selected;

  @override
  State<AppPickerPage> createState() => _AppPickerPageState();
}

class _AppPickerPageState extends State<AppPickerPage> {
  late final Set<String> _chosen = {for (final app in widget.selected) app.package};
  final _query = TextEditingController();

  late final List<TrackedApp> _all = [
    ...widget.available,
    for (final app in widget.selected)
      if (!widget.available.contains(app)) app,
  ];

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _done() => Navigator.pop(context, [
        for (final app in _all)
          if (_chosen.contains(app.package)) app,
      ]);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final query = _query.text.trim().toLowerCase();
    // Les applications cochees d'abord : ce sont elles qu'on vient verifier.
    final shown = [
      for (final app in _all)
        if (query.isEmpty ||
            app.label.toLowerCase().contains(query) ||
            app.package.toLowerCase().contains(query))
          app,
    ]..sort((a, b) {
        final chosen = (_chosen.contains(b.package) ? 1 : 0) - (_chosen.contains(a.package) ? 1 : 0);
        return chosen != 0 ? chosen : a.label.toLowerCase().compareTo(b.label.toLowerCase());
      });

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.free_apps_title),
        actions: [
          TextButton(
            onPressed: _chosen.isEmpty ? null : _done,
            child: Text(l10n.free_apps_done(_chosen.length)),
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: _query,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: l10n.free_apps_search,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? Center(child: Text(l10n.free_apps_none))
              : ListView.builder(
                  itemCount: shown.length,
                  itemBuilder: (context, index) {
                    final app = shown[index];
                    return CheckboxListTile(
                      value: _chosen.contains(app.package),
                      title: Text(app.label),
                      subtitle: Text(app.package, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onChanged: (checked) => setState(() {
                        if (checked == true) {
                          _chosen.add(app.package);
                        } else {
                          _chosen.remove(app.package);
                        }
                      }),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

/// Les applications suivies, en une ligne : « Instagram, YouTube et 2 autres ».
String appsSummary(AppLocalizations l10n, List<TrackedApp> apps) {
  if (apps.isEmpty) {
    return l10n.free_apps_empty;
  }
  if (apps.length <= 2) {
    return apps.map((app) => app.label).join(', ');
  }
  return l10n.free_apps_summary('${apps[0].label}, ${apps[1].label}', apps.length - 2);
}
