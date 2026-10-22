/// Route-local presentation state, retained by Flutter's PageStorage when a
/// tab unmounts. This is not session persistence and does not survive app exit.
class AssistantViewState {
  AssistantViewState({
    required Map<String, String> drafts,
    required Map<String, double> offsets,
  }) : drafts = Map.of(drafts),
       offsets = Map.of(offsets);

  final Map<String, String> drafts;
  final Map<String, double> offsets;
}
