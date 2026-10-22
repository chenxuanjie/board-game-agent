import 'package:webdav_sync/webdav_sync.dart' show canonicalJson;
import '../models/remote_library_update.dart';

/// Catalogs are overlays: a missing entry does not delete a bundled game.
List<RemoteLibraryChange> catalogChanges(
  Map<String, dynamic> local,
  Map<String, dynamic> remote,
) {
  final previous = {
    for (final entry in (local['games'] as List? ?? []))
      (entry as Map)['slug']: entry,
  };
  return [
    for (final entry in (remote['games'] as List? ?? []))
      if (canonicalJson(previous[(entry as Map)['slug']]) !=
          canonicalJson(entry))
        RemoteLibraryChange(
          path: 'assets/games/${entry['slug']}/game.json',
          title: entry['slug'] as String,
          kind: previous[entry['slug']] == null
              ? RemoteLibraryChangeKind.added
              : entry['enabled'] == false &&
                    (previous[entry['slug']] as Map)['enabled'] == true
              ? RemoteLibraryChangeKind.disabled
              : RemoteLibraryChangeKind.modified,
          fields: [
            for (final key in ['enabled', 'order', 'browseCategories'])
              if (canonicalJson((previous[entry['slug']])?[key]) !=
                  canonicalJson(entry[key]))
                key,
          ],
        ),
  ];
}

List<String> changedMetadataFields(
  Map<String, dynamic> local,
  Map<String, dynamic> remote,
) => [
  for (final key in {...local.keys, ...remote.keys})
    if (canonicalJson(local[key]) != canonicalJson(remote[key])) key,
];

Map<String, String> metadataValueChanges(
  Map<String, dynamic> local,
  Map<String, dynamic> remote,
) {
  String? visible(Object? value) {
    if (value is num) return '$value';
    if (value is String && value.length <= 80) return value;
    if (value is List && value.length <= 10 && value.every((v) => v is num)) {
      return value.join(' / ');
    }
    return null;
  }

  return {
    for (final key in ['score', 'supportedPlayers', 'recommendedPlayer'])
      if (canonicalJson(local[key]) != canonicalJson(remote[key]) &&
          visible(local[key]) != null &&
          visible(remote[key]) != null)
        key: '${visible(local[key])} → ${visible(remote[key])}',
  };
}
