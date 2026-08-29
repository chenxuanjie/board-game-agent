/// Lifecycle state for a network-backed service check.
///
/// `loading` is deliberately part of the shared status model rather than a
/// widget-local boolean so every surface can render the same observable
/// state while a request is in flight.
enum ConnectivityState { success, warning, failure, loading, unknown }

class ConnectivityStatus {
  const ConnectivityStatus({
    required this.state,
    required this.message,
    required this.checkedAt,
  });

  final ConnectivityState state;
  final String message;
  final DateTime checkedAt;

  bool get isLoading => state == ConnectivityState.loading;

  static ConnectivityStatus unknown([String message = '未检测']) {
    return ConnectivityStatus(
      state: ConnectivityState.unknown,
      message: message,
      checkedAt: DateTime.now(),
    );
  }
}
