import 'dart:convert';

import 'package:i_zerak_app/models/torrent_state.dart';

/// Un torrent, tel que renvoye par `GET /api/v2/torrents/info`.
///
/// Le parsing est volontairement defensif : les champs varient d'une version de
/// qBittorrent a l'autre, et un champ absent ne doit pas faire tomber la liste
/// entiere.
class TorrentDao {
  const TorrentDao({
    required this.hash,
    required this.name,
    required this.progress,
    required this.dlspeed,
    required this.upspeed,
    required this.size,
    required this.eta,
    required this.ratio,
    required this.state,
    required this.category,
    required this.savePath,
    required this.tags,
    required this.addedOn,
  });

  final String hash;
  final String name;

  /// Entre 0 et 1.
  final double progress;
  final int dlspeed;
  final int upspeed;
  final int size;
  final int eta;
  final double ratio;
  final TorrentState state;
  final String category;
  final String savePath;
  final List<String> tags;

  /// Horodatage Unix en secondes.
  final int addedOn;

  factory TorrentDao.fromJson(Map<String, dynamic> json) => TorrentDao(
        hash: json['hash'] as String? ?? '',
        name: json['name'] as String? ?? '',
        // progress et ratio remontent parfois en entier (0 ou 1) : un cast
        // direct en double leverait.
        progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
        dlspeed: (json['dlspeed'] as num?)?.toInt() ?? 0,
        upspeed: (json['upspeed'] as num?)?.toInt() ?? 0,
        size: (json['size'] as num?)?.toInt() ?? 0,
        eta: (json['eta'] as num?)?.toInt() ?? -1,
        ratio: (json['ratio'] as num?)?.toDouble() ?? 0.0,
        state: TorrentState.fromApi(json['state'] as String?),
        category: json['category'] as String? ?? '',
        savePath: json['save_path'] as String? ?? '',
        // tags est une chaine separee par des virgules, pas un tableau.
        tags: _parseTags(json['tags']),
        addedOn: (json['added_on'] as num?)?.toInt() ?? 0,
      );

  static List<String> _parseTags(Object? raw) {
    if (raw is! String || raw.isEmpty) {
      return const [];
    }
    return raw
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList(growable: false);
  }

  static List<TorrentDao> listFromBody(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! List) {
      return const [];
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(TorrentDao.fromJson)
        .toList(growable: false);
  }

  @override
  String toString() => 'TorrentDao($hash, $name, ${state.name})';
}
