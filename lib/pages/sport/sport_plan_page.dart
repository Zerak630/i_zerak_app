import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/sport_dao.dart';
import 'package:i_zerak_app/pages/sport/widgets/sport_sheets.dart';
import 'package:i_zerak_app/pages/sport/widgets/sport_ui.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_sport.dart';

/// Le programme de la semaine, et les sports pratiques.
///
/// Le programme ne cree aucune seance : il pose chaque semaine des creneaux
/// qui attendent qu'on dise s'ils ont ete faits.
class SportPlanPage extends StatefulWidget {
  const SportPlanPage({super.key, required this.store});

  final ISport store;

  @override
  State<SportPlanPage> createState() => _SportPlanPageState();
}

class _SportPlanPageState extends State<SportPlanPage> {
  List<Sport> _sports = const [];
  List<PlannedSlot> _plan = const [];
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final sports = await widget.store.getSports();
    final plan = await widget.store.getPlan();
    if (!mounted) {
      return;
    }
    setState(() {
      _sports = sports;
      _plan = [...plan]..sort((a, b) {
          final byDay = a.weekday.compareTo(b.weekday);
          return byDay != 0 ? byDay : a.id.compareTo(b.id);
        });
      _loading = false;
    });
  }

  Sport? _sport(String id) {
    for (final sport in _sports) {
      if (sport.id == id) {
        return sport;
      }
    }
    return null;
  }

  Future<void> _edit([PlannedSlot? slot]) async {
    final edited = await showSlotEditor(context, sports: _sports, slot: slot);
    if (edited == null) {
      return;
    }
    await widget.store.saveSlot(edited);
    await _reload();
  }

  Future<void> _delete(PlannedSlot slot) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.sport_plan_delete),
        content: Text(l10n.sport_plan_delete_hint),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.delete)),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.store.deleteSlot(slot.id);
      await _reload();
    }
  }

  Future<void> _addSport() async {
    final sport = await showNewSportSheet(context);
    if (sport == null) {
      return;
    }
    await widget.store.saveSport(sport);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = SportFormat(context);
    final weekly = _plan.fold(0, (sum, slot) => sum + slot.minutes);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.sport_plan_title)),
      floatingActionButton: _loading
          ? null
          : FloatingActionButton.extended(
              onPressed: _edit,
              icon: const Icon(Icons.add),
              label: Text(l10n.sport_plan_add),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                Text(
                  l10n.sport_plan_hint,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
                ),
                const SizedBox(height: 12),
                if (_plan.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      l10n.sport_plan_empty,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleSmall?.copyWith(color: scheme.outline),
                    ),
                  )
                else ...[
                  for (final slot in _plan)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        onTap: () => _edit(slot),
                        onLongPress: () => _delete(slot),
                        leading: SportAvatar(
                          sport: _sport(slot.sportId),
                          color: sportColor(scheme, _sports, slot.sportId),
                        ),
                        title: Text(sportLabel(l10n, _sport(slot.sportId))),
                        subtitle: Text(format.weekday(slot.weekday)),
                        trailing: Text(sportMinutes(l10n, slot.minutes), style: theme.textTheme.labelLarge),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      l10n.sport_plan_total(_plan.length, sportMinutes(l10n, weekly)),
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Row(children: [
                  Expanded(child: Text(l10n.sport_my_sports, style: theme.textTheme.titleMedium)),
                  TextButton.icon(
                    onPressed: _addSport,
                    icon: const Icon(Icons.add),
                    label: Text(l10n.sport_add_sport),
                  ),
                ]),
                const SizedBox(height: 4),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final sport in _sports)
                    Chip(
                      avatar: Icon(sportIconData(sport.icon), size: 18,
                          color: sportColor(scheme, _sports, sport.id)),
                      label: Text(sportLabel(l10n, sport)),
                    ),
                ]),
              ],
            ),
    );
  }
}
