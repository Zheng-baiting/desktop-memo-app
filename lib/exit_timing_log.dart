import 'dart:async';
import 'dart:convert';
import 'dart:io';

// Only fixed stage names and anonymous ordinal numbers enter the log.
enum ExitStage {
  noteRequest,
  saveCurrentNote,
  sendExitRequest,
  shutdown,
  saveNote,
  saveAll,
  notifications,
  tray,
  closeWindows,
}

class ExitTimingLog {
  ExitTimingLog({File? file})
    : file = file ?? defaultFile,
      session = DateTime.now().microsecondsSinceEpoch.toString();

  static File get defaultFile => File(
    '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}'
    'logs${Platform.pathSeparator}exit-timing.jsonl',
  );
  static const maxBytes = 256 * 1024;
  final File file;
  final String session;
  final Stopwatch _total = Stopwatch()..start();
  bool _writable = true;

  void _record(ExitStage stage, String event, int elapsedMs, int? noteIndex) {
    if (!_writable) return;
    try {
      file.parent.createSync(recursive: true);
      // Two bounded files; never retain an unlimited history of exit attempts.
      if (file.existsSync() && file.lengthSync() >= maxBytes) {
        final previous = File('${file.path}.previous');
        if (previous.existsSync()) previous.deleteSync();
        file.renameSync(previous.path);
      }
      file.writeAsStringSync(
        '${jsonEncode({'time': DateTime.now().toUtc().toIso8601String(), 'session': session, 'stage': stage.name, 'event': event, 'elapsed_ms': elapsedMs, 'total_ms': _total.elapsedMilliseconds, 'note_index': ?noteIndex})}\n',
        mode: FileMode.append,
      );
    } catch (_) {
      // A read-only install or full disk must not prevent saving or exiting.
      // Do not write exception messages: they may contain private file paths.
      _writable = false;
    }
  }

  Future<T> measure<T>(
    ExitStage stage,
    Future<T> Function() action, {
    int? noteIndex,
  }) async {
    final watch = Stopwatch()..start();
    _record(stage, 'start', 0, noteIndex);
    final waiting = Timer.periodic(const Duration(seconds: 2), (_) {
      _record(stage, 'waiting', watch.elapsedMilliseconds, noteIndex);
    });
    try {
      final result = await action();
      _record(stage, 'done', watch.elapsedMilliseconds, noteIndex);
      return result;
    } catch (_) {
      _record(stage, 'failed', watch.elapsedMilliseconds, noteIndex);
      rethrow;
    } finally {
      waiting.cancel();
    }
  }
}
