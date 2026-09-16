import 'dart:io';

/// App-wide internet gate. Local files still work; HTTP does not.
class NetworkGate {
  static bool offline = false;

  static void requireOnline() {
    if (offline) {
      throw const SocketException('offline');
    }
  }
}
