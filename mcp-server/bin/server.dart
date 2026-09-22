import 'dart:async';
import 'dart:io';

import 'package:crusam_mcp/server.dart';
import 'package:dart_mcp/stdio.dart';

/// Entry point launched by Claude Desktop. stdout is the MCP channel; every
/// log line and any stray print() goes to stderr / the log file.
Future<void> main() async {
  await runZonedGuarded(
    () async {
      final ServerConfig config;
      try {
        config = ServerConfig.fromEnvironment();
      } on ConfigError catch (e) {
        stderr.writeln('crusam-mcp: configuration error: $e');
        exitCode = 78;
        return;
      }
      if (config.logFile != null) Log.openFile(config.logFile!);
      Log.info('crusam-mcp $serverVersion starting (pid $pid)');

      final store = await CrusamDb.open(config);
      final server = CrusamMcpServer(
        stdioChannel(input: stdin, output: stdout),
        ToolContext(store),
      );
      await server.done;
      await store.close();
      Log.info('crusam-mcp stopped');
      await Log.close();
    },
    (e, st) => Log.error('Unhandled error', e, st),
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => Log.info('print: $line'),
    ),
  );
}
