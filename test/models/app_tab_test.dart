import 'package:i_zerak_app/models/app_tab.dart';
import 'package:test/test.dart';

void main() {
  test('la barre d origine porte trois onglets', () {
    expect(TabLayout.initial.pinned, hasLength(3));
    expect(TabLayout.initial.canPinMore, isFalse);
    expect(TabLayout.initial.others, hasLength(AppTab.values.length - 3));
  });

  test('epingler un quatrieme onglet ne chasse personne', () {
    final full = TabLayout.initial;

    final unchanged = full.pin(AppTab.system);

    expect(identical(unchanged, full), isTrue);
    expect(unchanged.isPinned(AppTab.system), isFalse);
  });

  test('retirer puis ajouter change la composition de la barre', () {
    final layout = TabLayout.initial.unpin(AppTab.subscriptions).pin(AppTab.system);

    expect(layout.isPinned(AppTab.subscriptions), isFalse);
    expect(layout.isPinned(AppTab.system), isTrue);
    expect(layout.pinned, hasLength(3));
    // L'onglet ajoute prend la derniere place, celle du bouton qu'il remplace.
    expect(layout.pinned.last, AppTab.system);
  });

  test('le dernier onglet epingle ne part pas', () {
    var layout = const TabLayout([AppTab.home]);

    layout = layout.unpin(AppTab.home);

    expect(layout.pinned, [AppTab.home]);
  });

  test('un onglet deja epingle ne se duplique pas', () {
    final layout = TabLayout.initial.pin(AppTab.home);

    expect(layout.pinned.where((tab) => tab == AppTab.home), hasLength(1));
  });

  group('relecture', () {
    test('un aller-retour conserve l ordre choisi', () {
      const layout = TabLayout([AppTab.commute, AppTab.gas]);

      final read = TabLayout.fromNames(layout.toNames());

      expect(read.pinned, [AppTab.commute, AppTab.gas]);
    });

    test('un nom inconnu est ignore', () {
      final read = TabLayout.fromNames(['commute', 'onglet-supprime', 'gas']);

      expect(read.pinned, [AppTab.commute, AppTab.gas]);
    });

    test('une preference vide ou abimee retombe sur la barre d origine', () {
      expect(TabLayout.fromNames(const []).pinned, TabLayout.initial.pinned);
      expect(TabLayout.fromNames([1, null, true]).pinned, TabLayout.initial.pinned);
    });

    test('une preference trop longue est tronquee a trois', () {
      final read = TabLayout.fromNames(
          [for (final tab in AppTab.values) tab.name]);

      expect(read.pinned, hasLength(3));
    });

    test('un doublon ne prend pas deux places', () {
      final read = TabLayout.fromNames(['home', 'home', 'gas']);

      expect(read.pinned, [AppTab.home, AppTab.gas]);
    });
  });
}
