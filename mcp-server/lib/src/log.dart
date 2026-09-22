import 'dart:io';

/// stdout carries the MCP protocol, so logs go to stderr and optionally a
/// file. Nothing in this server may write to stdout.
class Log {
  Log._();

  static IOSink? _file;

  static void openFile(String path) {
    final f = File(path);
    f.parent.createSync(recursive: true);
    _file = f.openWrite(mode: FileMode.append);
  }

  static void info(String msg) => _write('INFO', msg);
  static void warn(String msg) => _write('WARN', msg);
  static void error(String msg, [Object? e, StackTrace? st]) =>
      _write('ERROR', [msg, if (e != null) '$e', if (st != null) '$st'].join('\n'));

  static void _write(String level, String msg) {
    final line = '${DateTime.now().toIso8601String()} [$level] $msg';
    stderr.writeln(line);
    _file?.writeln(line);
  }

  static Future<void> close() async => _file?.close();
}
