import 'package:flutter/material.dart';

/// Une categorie des reglages : un en-tete qu'on touche pour replier ou
/// deplier, et son contenu.
///
/// Le contenu n'est construit qu'a la premiere ouverture — certaines
/// categories interrogent le reseau ou le stockage securise — puis il reste
/// en vie une fois replie : une saisie en cours ne se perd pas parce qu'on a
/// replie pour regarder ailleurs.
class SettingsCategoryCard extends StatefulWidget {
  const SettingsCategoryCard({
    super.key,
    required this.icon,
    required this.title,
    required this.hint,
    required this.expanded,
    required this.onToggle,
    required this.builder,
  });

  final IconData icon;
  final String title;

  /// Ce qu'on y trouve, en une ligne : l'ecran replie sert de sommaire.
  final String hint;
  final bool expanded;
  final VoidCallback onToggle;
  final WidgetBuilder builder;

  @override
  State<SettingsCategoryCard> createState() => _SettingsCategoryCardState();
}

class _SettingsCategoryCardState extends State<SettingsCategoryCard> {
  late bool _built = widget.expanded;

  @override
  void didUpdateWidget(SettingsCategoryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expanded) {
      _built = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: widget.onToggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(children: [
              Icon(widget.icon, color: scheme.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    widget.hint,
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ]),
              ),
              AnimatedRotation(
                turns: widget.expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(Icons.expand_more, color: scheme.onSurfaceVariant),
              ),
            ]),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: !_built
              ? const SizedBox(width: double.infinity)
              : Visibility(
                  visible: widget.expanded,
                  maintainState: true,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Builder(builder: widget.builder),
                  ),
                ),
        ),
      ]),
    );
  }
}

/// Un intertitre au sein d'une categorie.
class SettingsSubtitle extends StatelessWidget {
  const SettingsSubtitle(this.text, {super.key, this.first = false});

  final String text;

  /// Le premier n'a pas besoin de s'eloigner de l'en-tete.
  final bool first;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(top: first ? 4 : 24, bottom: 12),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelMedium?.copyWith(
          letterSpacing: 0.9,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// Une heure qu'on touche pour la changer.
class SettingsTimeTile extends StatelessWidget {
  const SettingsTimeTile({
    super.key,
    required this.title,
    required this.hour,
    required this.minute,
    required this.enabled,
    required this.onChanged,
  });

  final String title;
  final int hour;
  final int minute;
  final bool enabled;
  final ValueChanged<TimeOfDay> onChanged;

  @override
  Widget build(BuildContext context) {
    final time = TimeOfDay(hour: hour, minute: minute);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.schedule),
      title: Text(title),
      trailing: Text(time.format(context), style: Theme.of(context).textTheme.titleSmall),
      enabled: enabled,
      onTap: () async {
        final picked = await showTimePicker(context: context, initialTime: time);
        if (picked != null) {
          onChanged(picked);
        }
      },
    );
  }
}

/// Le temps qu'une categorie lise ce qu'elle affiche.
class SettingsLoading extends StatelessWidget {
  const SettingsLoading({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
}
