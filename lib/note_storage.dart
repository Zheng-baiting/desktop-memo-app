import 'dart:convert';
import 'dart:io';

/// Windows packaged and scheduled launches must read the same physical file.
/// AppData can be redirected by a packaged launcher; Documents is shared.
class NoteStorage {
  NoteStorage(this.file);
  final File file;
  String? _lastRead;
  bool _loaded = false;

  static NoteStorage windowsDefault() {
    final home = Platform.environment['USERPROFILE'];
    if (home == null) throw StateError('无法找到用户文档目录');
    return NoteStorage(File('$home/Documents/桌面便利贴数据/notes.json'));
  }

  String? read(String? legacy) {
    return _locked(() {
      final stored = file.existsSync() ? file.readAsStringSync() : null;
      final raw = stored ?? legacy;
      _validate(raw);
      _lastRead = stored;
      _loaded = true;
      return raw;
    });
  }

  Future<void> write(String raw) async {
    _validate(raw);
    _locked(() {
      final current = file.existsSync() ? file.readAsStringSync() : null;
      // A second process or a recovery must never be overwritten by stale memory.
      if (current != _lastRead || (!_loaded && current != null)) {
        throw StateError('存档已被另一实例更新，已停止覆盖。请先复制当前未保存的内容，再重新打开应用。');
      }
      final temporary = File('${file.path}.tmp');
      temporary.writeAsStringSync(raw, flush: true);
      temporary.renameSync(file.path);
      _lastRead = raw;
      _loaded = true;
    });
  }

  T _locked<T>(T Function() operation) {
    file.parent.createSync(recursive: true);
    final lock = File('${file.path}.lock').openSync(mode: FileMode.append);
    try {
      lock.lockSync(FileLock.blockingExclusive);
      return operation();
    } finally {
      lock.closeSync();
    }
  }

  void _validate(String? raw) {
    if (raw != null && jsonDecode(raw) is! List) {
      throw const FormatException('便利贴文件必须是列表');
    }
  }
}
