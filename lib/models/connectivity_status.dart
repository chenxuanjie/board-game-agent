enum ConnectivityState { success, warning, failure, unknown }

class ConnectivityStatus {
  const ConnectivityStatus({
    required this.state,
    required this.message,
    required this.checkedAt,
  });

  final ConnectivityState state;
  final String message;
  final DateTime checkedAt;

  static ConnectivityStatus unknown([String message = '未检测']) {
    return ConnectivityStatus(
      state: ConnectivityState.unknown,
      message: message,
      checkedAt: DateTime.now(),
    );
  }
}
