/// Formatage des grandeurs affichees par le module de telechargement.
///
/// Dart pur, sans `intl` : pas d'initialisation de locale a prevoir, et les
/// tests restent deterministes quelle que soit la machine.

const int _kilo = 1024;
const List<String> _units = ['o', 'Ko', 'Mo', 'Go', 'To', 'Po'];

/// Sentinelle renvoyee par qBittorrent pour un temps restant indetermine :
/// 8 640 000 secondes, soit cent jours.
const int kInfiniteEta = 8640000;

const String _infinite = '\u221e';
const String _unknown = '\u2014';

/// Taille en base 1024. Les octets bruts s'affichent sans decimale.
String formatBytes(int bytes, {int decimals = 1}) {
  if (bytes < 0) {
    return _unknown;
  }
  if (bytes < _kilo) {
    return '$bytes ${_units.first}';
  }

  var value = bytes.toDouble();
  var unit = 0;
  while (value >= _kilo && unit < _units.length - 1) {
    value /= _kilo;
    unit++;
  }
  return '${value.toStringAsFixed(decimals)} ${_units[unit]}';
}

String formatSpeed(int bytesPerSecond) {
  if (bytesPerSecond <= 0) {
    return '0 ${_units.first}/s';
  }
  return '${formatBytes(bytesPerSecond)}/s';
}

/// Duree restante, compacte. Renvoie l'infini pour la sentinelle de
/// qBittorrent comme pour toute valeur negative.
String formatEta(int seconds) {
  if (seconds < 0 || seconds >= kInfiniteEta) {
    return _infinite;
  }
  return _formatDuration(seconds);
}

String _formatDuration(int seconds) {
  if (seconds < 60) {
    return '${seconds}s';
  }
  if (seconds < 3600) {
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return rest == 0 ? '${minutes}min' : '${minutes}min ${rest}s';
  }
  if (seconds < 86400) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    return minutes == 0 ? '${hours}h' : '${hours}h ${minutes}min';
  }
  final days = seconds ~/ 86400;
  final hours = (seconds % 86400) ~/ 3600;
  return hours == 0 ? '${days}j' : '${days}j ${hours}h';
}

/// Avancement en pourcentage. Cent pour cent s'affiche sans decimale.
String formatProgress(double progress) {
  final clamped = progress.clamp(0.0, 1.0) * 100;
  if (clamped >= 100) {
    return '100 %';
  }
  return '${clamped.toStringAsFixed(1)} %';
}

/// Ratio de partage. qBittorrent renvoie -1 lorsqu'il est indefini.
String formatRatio(double ratio) => ratio < 0 ? _infinite : ratio.toStringAsFixed(2);

/// Duree de fonctionnement. Contrairement a [formatEta], aucune sentinelle ne
/// s'applique : un Raspberry Pi peut tourner plus de cent jours, et cette duree
/// doit rester lisible telle quelle.
String formatUptime(int seconds) => seconds < 0 ? _unknown : _formatDuration(seconds);
