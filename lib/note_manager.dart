part of 'main.dart';

class NoteManager extends StatefulWidget {
  const NoteManager({
    super.key,
    required this.notes,
    required this.visibleIds,
    required this.toolbar,
    required this.onOpen,
    required this.onNew,
  });
  final List<Memo> notes;
  final Set<String> visibleIds;
  final Widget toolbar;
  final ValueChanged<Memo> onOpen;
  final VoidCallback onNew;

  @override
  State<NoteManager> createState() => _NoteManagerState();
}

class _NoteManagerState extends State<NoteManager> {
  final search = TextEditingController();
  String query = '';

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  String _reminder(BuildContext context, Memo note) {
    final when = note.nextAlertAt;
    if (when == null) return '未设提醒';
    final locale = MaterialLocalizations.of(context);
    final date = Memo.dateKey(when);
    final time = locale.formatTimeOfDay(
      TimeOfDay.fromDateTime(when),
      alwaysUse24HourFormat: true,
    );
    return '${note.snoozedUntil != null ? '稍后提醒' : '提醒'}：$date $time';
  }

  @override
  Widget build(BuildContext context) {
    final visibleCount = widget.notes
        .where((note) => widget.visibleIds.contains(note.id))
        .length;
    final matches =
        widget.notes
            .where(
              (note) =>
                  query.isEmpty ||
                  note.title.toLowerCase().contains(query) ||
                  note.body.toLowerCase().contains(query),
            )
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            widget.toolbar,
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${widget.notes.length} 张便签 · $visibleCount 张显示中 · ${widget.notes.length - visibleCount} 张已收起',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '收起的便签仍保留内容。点击“打开”即可找回；退出应用会保存全部记录。',
                    style: TextStyle(color: memoMuted),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const ValueKey('note-search'),
                    controller: search,
                    onChanged: (value) =>
                        setState(() => query = value.trim().toLowerCase()),
                    decoration: InputDecoration(
                      hintText: '搜索标题或正文',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: '清除搜索',
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                search.clear();
                                setState(() => query = '');
                              },
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: widget.notes.isEmpty
                  ? Center(
                      child: FilledButton.icon(
                        onPressed: widget.onNew,
                        icon: const Icon(Icons.add),
                        label: const Text('创建第一张便利贴'),
                      ),
                    )
                  : matches.isEmpty
                  ? const Center(child: Text('没有匹配的便利贴，试试其他关键词'))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                      itemCount: matches.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, indent: 56),
                      itemBuilder: (context, index) {
                        final note = matches[index];
                        final visible = widget.visibleIds.contains(note.id);
                        return ListTile(
                          key: ValueKey('manager-${note.id}'),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          leading: Icon(
                            Icons.sticky_note_2_outlined,
                            color: memoAccent,
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  note.title.isEmpty ? '未命名便利贴' : note.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                visible ? '显示中' : '已收起',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: memoMuted,
                                ),
                              ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (note.body.trim().isNotEmpty)
                                Text(
                                  note.body
                                      .replaceAll(RegExp(r'\s+'), ' ')
                                      .trim(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              Text(
                                _reminder(context, note),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: memoMuted,
                                ),
                              ),
                            ],
                          ),
                          trailing: TextButton(
                            onPressed: () => widget.onOpen(note),
                            child: Text(visible ? '定位' : '打开'),
                          ),
                          onTap: () => widget.onOpen(note),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
