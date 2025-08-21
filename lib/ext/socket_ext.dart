import 'dart:io';

import '../ext/log_ext.dart';

/// HTTP request terminator sequence, used to indicate the end of HTTP headers.
const String httpTerminal = '\r\n\r\n';

/// Safe per-write size to avoid iOS send-buffer issues (~97.7 KB).
const int _chunk = 100000;

/// Extension on the [Socket] class to provide additional utility methods.
extension SocketExtension on Socket {
  /// Configure Darwin (iOS/macOS) sockets to avoid SIGPIPE on writes.
  void configureForApple() {
    if (Platform.isIOS || Platform.isMacOS) {
      // SO_NOSIGPIPE = 0x1022 on Darwin
      setRawOption(
        RawSocketOption.fromInt(RawSocketOption.levelSocket, 0x1022, 1),
      );
    }
  }

  /// Appends data to the socket.
  ///
  /// - String: writes string + HTTP terminal then flushes.
  /// - Stream<List<int>>: pipes stream then flushes.
  /// - List<int>: on iOS, writes in chunks with flush between chunks; otherwise writes once and flushes.
  ///
  /// Returns `true` if the operation succeeds; logs and returns `false` on error.
  Future<bool> append(Object data) async {
    try {
      if (data is String) {
        write('$data$httpTerminal');
        await flush();
        return true;
      }

      if (data is Stream<List<int>>) {
        await addStream(data);
        await flush();
        return true;
      }

      if (data is List<int>) {
        if (Platform.isIOS) {
          for (int start = 0; start < data.length; start += _chunk) {
            final int end = (start + _chunk <= data.length)
                ? start + _chunk
                : data.length;
            add(data.sublist(start, end));
            await flush(); // surfaces write errors here instead of SIGPIPE
            await Future.delayed(
              const Duration(milliseconds: 10),
            ); // small yield
          }
        } else {
          add(data);
          await flush();
        }
        return true;
      }

      // Unknown type
      logW('append: unsupported data type ${data.runtimeType}');
      return false;
    } catch (e, st) {
      // If SO_NOSIGPIPE is not set on iOS/macOS and peer closed, the process may be killed before this.
      // Call `socket.configureForApple()` right after creating the socket.
      logW("Socket closed: $e, can't append data\n$st");
      return false;
    }
  }
}
