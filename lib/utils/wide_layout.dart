import 'package:flutter/widgets.dart';

/// Les largeurs a partir desquelles l'application quitte sa mise en page de
/// telephone.
///
/// Decide par la place disponible, jamais par la plateforme : une fenetre
/// Windows etroite garde la barre du bas, une tablette en paysage prend le
/// rail. Les memes pages servent ainsi partout.
abstract final class WideLayout {
  /// La barre du bas devient un rail a gauche.
  static const double rail = 700;

  /// Le rail deplie ses libelles : en dessous, ils mangeraient la page.
  static const double extendedRail = 1100;

  /// Assez large pour poser les cartes cote a cote plutot qu'en pile.
  static const double twoColumns = 760;
  static const double threeColumns = 1180;

  /// Au-dela, la page reste centree : assez pour trois colonnes de cartes.
  static const double maxContentWidth = 1240;

  static bool hasRail(BuildContext context) => MediaQuery.sizeOf(context).width >= rail;
}
