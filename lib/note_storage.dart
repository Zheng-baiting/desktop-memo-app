import 'dart:convert';
import 'dart:io';

/// Windows packaged and scheduled launches must read the same physical file.
/// AppData can be redirected by a packaged launcher; Documents is shared.
class NoteStorage {
  NoteStorage(this.file);
  final File file;

  static NoteStorage windowsDefault() {
    final home = Platform.environment['USERPROFILE'];
    if (home == null) throw StateError('无法找到用户文档目录');
    return NoteStorage(File('$home/Documents/桌面便利贴数据/notes.json'));
  }

  String? read(String? legacy) {
    final raw = file.existsSync() ? file.readAsStringSync() : legacy;
    if (raw != null && jsonDecode(raw) is! List) {
      throw const FormatException('便利贴文件必须是列表');
    }
    return raw;
  }

  Future<void> write(String raw) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(raw, flush: true);
    await temporary.rename(file.path);
  }
}
