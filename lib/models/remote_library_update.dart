class RemoteLibraryUpdate {
  const RemoteLibraryUpdate({
    required this.changedPaths,
    required this.changedGameTitles,
  });

  final List<String> changedPaths;
  final List<String> changedGameTitles;

  int get changedCount => changedPaths.length;
}
