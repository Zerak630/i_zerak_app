import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/subscription_dao.dart';

/// Formats de l'onglet Abonnements, dans la langue de l'application.
///
/// `intl` plutot que `toStringAsFixed` : le total s'affiche « 220,35 € » en
/// francais, et une virgule decimale oubliee se voit tout de suite sur un
/// montant mis en avant.
class SubscriptionFormat {
  SubscriptionFormat(BuildContext context)
      : _locale = Localizations.localeOf(context).toLanguageTag();

  final String _locale;

  String euros(double value) =>
      NumberFormat.currency(locale: _locale, symbol: '€', decimalDigits: 2).format(value);

  String percent(double ratio) => NumberFormat.percentPattern(_locale).format(ratio);

  /// « vendredi 18 septembre »
  String longDay(DateTime day) => DateFormat('EEEE d MMMM', _locale).format(day);

  /// « ven. 18 sept. »
  String shortDay(DateTime day) => DateFormat('E d MMM', _locale).format(day);

  /// « mardi », pour dire quel jour revient chaque semaine.
  String weekday(DateTime day) => DateFormat('EEEE', _locale).format(day);

  /// « 18 septembre 2026 »
  String fullDate(DateTime day) => DateFormat('d MMMM y', _locale).format(day);

  /// « Septembre 2026 »
  String month(DateTime day) => _capitalize(DateFormat('MMMM y', _locale).format(day));

  /// Initiale du jour de la semaine, lundi en tete.
  List<String> weekdayInitials() => [
        for (var i = 0; i < 7; i++)
          // Le 1er janvier 2024 est un lundi.
          DateFormat('EEEEE', _locale).format(DateTime(2024, 1, 1 + i)).toUpperCase(),
      ];

  static String _capitalize(String text) =>
      text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';
}

/// Lit un montant saisi au clavier, virgule ou point.
double? parseAmount(String raw) =>
    double.tryParse(raw.trim().replaceAll(RegExp(r'\s'), '').replaceAll(',', '.'));

/// « Mensuel », la facturation de l'abonnement.
String frequencyLabel(AppLocalizations l10n, SubscriptionFrequency frequency) =>
    switch (frequency) {
      SubscriptionFrequency.weekly => l10n.per_week_adjective,
      SubscriptionFrequency.monthly => l10n.per_month_adjective,
      SubscriptionFrequency.yearly => l10n.per_year_adjective,
    };

/// « par mois », l'unite dans laquelle la page ramene tous les montants.
String unitLabel(AppLocalizations l10n, SubscriptionFrequency unit) => switch (unit) {
      SubscriptionFrequency.weekly => l10n.per_week,
      SubscriptionFrequency.monthly => l10n.per_month,
      SubscriptionFrequency.yearly => l10n.per_year,
    };

/// « sem. », « mois », « an » : le selecteur d'unite en haut de la page.
String unitShortLabel(AppLocalizations l10n, SubscriptionFrequency unit) => switch (unit) {
      SubscriptionFrequency.weekly => l10n.sub_unit_week,
      SubscriptionFrequency.monthly => l10n.sub_unit_month,
      SubscriptionFrequency.yearly => l10n.sub_unit_year,
    };

/// « Coût mensuel »
String costTitle(AppLocalizations l10n, SubscriptionFrequency unit) => switch (unit) {
      SubscriptionFrequency.weekly => l10n.sub_cost_week,
      SubscriptionFrequency.monthly => l10n.sub_cost_month,
      SubscriptionFrequency.yearly => l10n.sub_cost_year,
    };

/// Libelle d'une categorie : localise pour celles livrees, tel que saisi pour
/// les autres. Renommer une categorie renomme aussi l'historique, puisque les
/// abonnements n'en retiennent que l'identifiant.
String categoryLabel(AppLocalizations l10n, SubscriptionCategory category) =>
    category.label ??
    switch (category.id) {
      SubscriptionCategory.home => l10n.category_home,
      SubscriptionCategory.insurance => l10n.category_insurance,
      SubscriptionCategory.sport => l10n.category_sport,
      SubscriptionCategory.video => l10n.category_video,
      SubscriptionCategory.telecom => l10n.category_telecom,
      SubscriptionCategory.music => l10n.category_music,
      SubscriptionCategory.software => l10n.category_software,
      _ => category.id,
    };

/// Libelle de la categorie d'un abonnement. Une categorie supprimee, ou jamais
/// choisie, retombe sur « Autre ».
String categoryLabelOf(
  AppLocalizations l10n,
  String? categoryId,
  List<SubscriptionCategory> categories,
) {
  for (final category in categories) {
    if (category.id == categoryId) {
      return categoryLabel(l10n, category);
    }
  }
  return l10n.sub_category_none;
}

SubscriptionCategory? findCategory(String? id, List<SubscriptionCategory> categories) {
  for (final category in categories) {
    if (category.id == id) {
      return category;
    }
  }
  return null;
}

/// Teintes des categories, declinees pour le theme clair et le theme sombre.
///
/// Le theme de l'application n'offre que trois accents, insuffisants pour
/// distinguer sept categories. Ces teintes s'en rapprochent et gardent le meme
/// ordre de luminosite dans les deux themes, pour que la barre de repartition
/// reste lisible de jour comme de nuit.
const Map<CategoryColor, ({Color light, Color dark})> _categoryPalette = {
  CategoryColor.mint: (light: Color(0xFF2F7D5B), dark: Color(0xFF9FD6B4)),
  CategoryColor.steel: (light: Color(0xFF46697C), dark: Color(0xFFB4CAD6)),
  CategoryColor.apricot: (light: Color(0xFF9C5124), dark: Color(0xFFF1A986)),
  CategoryColor.sky: (light: Color(0xFF1B6A8C), dark: Color(0xFF8BD0EF)),
  CategoryColor.gold: (light: Color(0xFF7A5A0B), dark: Color(0xFFE9C46A)),
  CategoryColor.lilac: (light: Color(0xFF5B55A6), dark: Color(0xFFC6C2EA)),
  CategoryColor.slate: (light: Color(0xFF4A606D), dark: Color(0xFF8FA3B0)),
};

Color categoryColor(BuildContext context, CategoryColor color) {
  final shades = _categoryPalette[color] ?? _categoryPalette[CategoryColor.slate]!;
  return Theme.of(context).brightness == Brightness.dark ? shades.dark : shades.light;
}

/// Couleur d'un abonnement : celle de sa categorie, ou une teinte neutre.
Color subscriptionColor(
  BuildContext context,
  String? categoryId,
  List<SubscriptionCategory> categories,
) {
  final category = findCategory(categoryId, categories);
  return category == null
      ? Theme.of(context).colorScheme.outline
      : categoryColor(context, category.color);
}

/// Les icones proposees, par usage.
///
/// Des constantes, et non un `IconData` construit a partir d'un nombre :
/// celui-ci empeche l'elagage des polices d'icones, et `flutter build apk`
/// echoue alors sans `--no-tree-shake-icons`.
const Map<String, List<String>> kSubscriptionIconGroups = {
  'home': ['basket', 'house', 'bulb', 'drop', 'leaf', 'cart'],
  'leisure': ['film', 'play', 'music', 'game', 'book', 'news'],
  'fitness': ['gym', 'bike', 'heart', 'ball', 'health', 'outdoor'],
  'services': ['car', 'shield', 'fuel', 'cloud', 'phone', 'card'],
};

const Map<String, IconData> kSubscriptionIcons = {
  'basket': Icons.shopping_basket_outlined,
  'house': Icons.home_outlined,
  'bulb': Icons.lightbulb_outline,
  'drop': Icons.water_drop_outlined,
  'leaf': Icons.eco_outlined,
  'cart': Icons.shopping_cart_outlined,
  'film': Icons.movie_outlined,
  'play': Icons.play_circle_outline,
  'music': Icons.music_note_outlined,
  'game': Icons.sports_esports_outlined,
  'book': Icons.menu_book_outlined,
  'news': Icons.newspaper,
  'gym': Icons.fitness_center,
  'bike': Icons.pedal_bike,
  'heart': Icons.favorite_outline,
  'ball': Icons.sports_soccer_outlined,
  'health': Icons.medical_services_outlined,
  'outdoor': Icons.terrain_outlined,
  'car': Icons.directions_car_outlined,
  'shield': Icons.shield_outlined,
  'fuel': Icons.local_gas_station_outlined,
  'cloud': Icons.cloud_outlined,
  'phone': Icons.smartphone,
  'card': Icons.subscriptions_outlined,
};

IconData subscriptionIcon(String? iconId) =>
    kSubscriptionIcons[iconId] ?? kSubscriptionIcons[kDefaultSubscriptionIcon]!;

String iconGroupLabel(AppLocalizations l10n, String group) => switch (group) {
      'home' => l10n.icon_group_home,
      'leisure' => l10n.icon_group_leisure,
      'fitness' => l10n.icon_group_fitness,
      _ => l10n.icon_group_services,
    };

/// La pastille d'icone d'un abonnement, teintee par sa categorie.
class SubscriptionAvatar extends StatelessWidget {
  const SubscriptionAvatar({
    super.key,
    required this.iconId,
    required this.color,
    this.size = 36,
    this.muted = false,
  });

  final String? iconId;
  final Color color;
  final double size;

  /// Un abonnement suspendu garde son icone, mais perd sa couleur : c'est ce
  /// qui distingue la section du bas au premier coup d'oeil.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = muted ? scheme.outline : color;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: muted ? scheme.surfaceContainerHighest : tint.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size / 3),
      ),
      child: Icon(subscriptionIcon(iconId), size: size * 0.53, color: tint),
    );
  }
}

/// Poignee et marges communes aux feuilles du bas de l'onglet.
class SubscriptionSheet extends StatelessWidget {
  const SubscriptionSheet({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        // Suit le clavier : la feuille d'edition a plusieurs champs, et un
        // bouton masque sous le clavier passerait pour un blocage.
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        ),
      );
}

/// Creation d'une categorie : un nom et une couleur.
Future<SubscriptionCategory?> showAddCategoryDialog(BuildContext context) =>
    showDialog<SubscriptionCategory>(
      context: context,
      builder: (_) => const _AddCategoryDialog(),
    );

class _AddCategoryDialog extends StatefulWidget {
  const _AddCategoryDialog();

  @override
  State<_AddCategoryDialog> createState() => _AddCategoryDialogState();
}

class _AddCategoryDialogState extends State<_AddCategoryDialog> {
  // Possede par l'etat, et non cree dans la fonction qui ouvre le dialogue :
  // le liberer au retour de `showDialog` le ferait pendant l'animation de
  // fermeture, alors que le champ s'affiche encore.
  final _controller = TextEditingController();
  var _color = CategoryColor.mint;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      return;
    }
    Navigator.pop(
      context,
      SubscriptionCategory(
        id: 'custom-${DateTime.now().microsecondsSinceEpoch}',
        label: name,
        color: _color,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.sub_new_category),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: l10n.sub_category_name),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final color in CategoryColor.values)
                Semantics(
                  selected: color == _color,
                  child: InkWell(
                    onTap: () => setState(() => _color = color),
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: categoryColor(context, color),
                        border: color == _color
                            ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 2.5)
                            : null,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        TextButton(onPressed: _submit, child: Text(l10n.add)),
      ],
    );
  }
}
