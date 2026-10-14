part of 'main.dart';

class DeletedNotesPage extends StatefulWidget {
  const DeletedNotesPage({
    super.key,
    required this.notes,
    required this.onRestore,
  });

  final List<Memo> notes;
  final Future<void> Function(Memo) onRestore;

  @override
  State<DeletedNotesPage> createState() => _DeletedNotesPageState();
}

class _DeletedNotesPageState extends State<DeletedNotesPage> {
  final Set<String> _restoring = {};

  Future<void> _restore(Memo note) async {
    if (_restoring.contains(note.id)) return;
    setState(() => _restoring.add(note.id));
    try {
      await widget.onRestore(note);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('恢复失败，便利贴仍保留在最近删除中，请重试。')));
      }
    } finally {
      if (mounted) setState(() => _restoring.remove(note.id));
    }
  }

  String _deletedTime(DateTime time) {
    final local = time.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '删除于 ${local.year}/${two(local.month)}/${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: memoPaper,
    appBar: AppBar(
      backgroundColor: memoPaper,
      foregroundColor: memoInk,
      leading: const BackButton(),
      title: const Text('最近删除'),
    ),
    body: SafeArea(
      child: widget.notes.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.restore_page_outlined, size: 48),
                    SizedBox(height: 16),
                    Text(
                      '没有最近删除的便利贴',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 18, color: memoInk),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '删除的便利贴会保留在这里，可以随时恢复。',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: memoMuted),
                    ),
                  ],
                ),
              ),
            )
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: widget.notes.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          '误删的便利贴可以在这里恢复。',
                          style: TextStyle(color: memoMuted),
                        ),
                      );
                    }
                    final note = widget.notes[index - 1];
                    final restoring = _restoring.contains(note.id);
                    final title = note.title.trim();
                    final body = note.body.trim();
                    return Card(
                      key: ValueKey('deleted-note-${note.id}'),
                      color: papers.first,
                      margin: EdgeInsets.zero,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        side: const BorderSide(color: memoDivider),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title.isEmpty ? '未命名便利贴' : title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: memoInk,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    body.isEmpty ? '（没有正文）' : body,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: memoMuted),
                                  ),
                                  if (note.deletedAt != null) ...[
                                    const SizedBox(height: 12),
                                    Text(
                                      _deletedTime(note.deletedAt!),
                                      style: const TextStyle(
                                        color: memoMuted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            TextButton.icon(
                              key: ValueKey('restore-deleted-note-${note.id}'),
                              onPressed: restoring
                                  ? null
                                  : () => _restore(note),
                              icon: restoring
                                  ? const SizedBox.square(
                                      dimension: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.restore, size: 20),
                              label: Text(restoring ? '恢复中' : '恢复'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
    ),
  );
}
