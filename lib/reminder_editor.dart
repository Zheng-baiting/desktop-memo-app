part of 'main.dart';

typedef ReminderSelection = ({DateTime when, String mode, DateTime? until});

class ReminderEditor extends StatefulWidget {
  const ReminderEditor({
    super.key,
    required this.note,
    required this.onBack,
    required this.onSave,
    required this.onCancel,
  });
  final Memo note;
  final VoidCallback onBack;
  final Future<void> Function(ReminderSelection) onSave;
  final Future<void> Function() onCancel;
  @override
  State<ReminderEditor> createState() => _ReminderEditorState();
}

class _ReminderEditorState extends State<ReminderEditor> {
  final form = GlobalKey<FormState>();
  late final date = TextEditingController(text: Memo.dateKey(initial));
  late final time = TextEditingController(
    text:
        '${initial.hour.toString().padLeft(2, '0')}:${initial.minute.toString().padLeft(2, '0')}',
  );
  late final until = TextEditingController(
    text: Memo.dateKey(
      widget.note.repeatUntil ?? initial.add(const Duration(days: 180)),
    ),
  );
  late final initial = widget.note.nextAlertAt?.isAfter(DateTime.now()) == true
      ? widget.note.nextAlertAt!
      : DateTime.now().add(const Duration(minutes: 10));
  late String mode = widget.note.daily
      ? 'daily'
      : widget.note.persistent
      ? 'repeat'
      : 'once';
  bool busy = false;
  String? error;
  String t(String zh, String en) => uiText(context, zh, en);
  DateTime? parseDate(String value) {
    final text = value.trim();
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) return null;
    final parsed = DateTime.tryParse(text);
    return parsed != null && Memo.dateKey(parsed) == text ? parsed : null;
  }

  @override
  void dispose() {
    date.dispose();
    time.dispose();
    until.dispose();
    super.dispose();
  }

  void quick(int minutes) {
    final next = DateTime.now().add(Duration(minutes: minutes));
    date.text = Memo.dateKey(next);
    time.text =
        '${next.hour.toString().padLeft(2, '0')}:${next.minute.toString().padLeft(2, '0')}';
    setState(() {
      mode = 'once';
      error = null;
    });
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    final day = parseDate(date.text)!;
    final clock = time.text.trim().split(':').map(int.parse).toList();
    final when = DateTime(day.year, day.month, day.day, clock[0], clock[1]);
    final end = mode == 'daily' ? parseDate(until.text)! : null;
    if (!when.isAfter(DateTime.now())) {
      setState(() => error = t('请选择未来时间', 'Choose a future time'));
      return;
    }
    if (end != null && end.isBefore(DateTime(day.year, day.month, day.day))) {
      setState(
        () =>
            error = t('结束日期不能早于开始日期', 'End date cannot precede the start date'),
      );
      return;
    }
    await run(() => widget.onSave((when: when, mode: mode, until: end)));
  }

  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(() => error = t('保存失败，请重试', 'Could not save. Try again.'));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 270,
    height: 250,
    child: Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 3,
      shadowColor: Theme.of(context).colorScheme.onSurface
          .withValues(alpha: .12),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: t('返回便利贴', 'Back to note'),
                  onPressed: busy ? null : widget.onBack,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.arrow_back, size: 18),
                ),
                Text(
                  t('设置提醒', 'Set reminder'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            Expanded(
              child: Form(
                key: form,
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            key: const ValueKey('reminder-date'),
                            controller: date,
                            enabled: !busy,
                            style: const TextStyle(fontSize: 13),
                            keyboardType: TextInputType.datetime,
                            decoration: InputDecoration(
                              labelText: t('日期', 'Date'),
                              hintText: 'YYYY-MM-DD',
                              isDense: true,
                            ),
                            validator: (value) => parseDate(value ?? '') == null
                                ? t('格式：年-月-日', 'Use YYYY-MM-DD')
                                : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            key: const ValueKey('reminder-time'),
                            controller: time,
                            enabled: !busy,
                            style: const TextStyle(fontSize: 13),
                            keyboardType: TextInputType.datetime,
                            decoration: InputDecoration(
                              labelText: t('24小时制', '24-hour time'),
                              hintText: 'HH:mm',
                              isDense: true,
                            ),
                            validator: (value) =>
                                RegExp(r'^([01]?\d|2[0-3]):[0-5]\d$')
                                    .hasMatch(value?.trim() ?? '')
                                ? null
                                : t('如 09:30', 'e.g. 09:30'),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (final minutes in [10, 30, 60])
                          Expanded(
                            child: TextButton(
                              style: TextButton.styleFrom(
                                minimumSize: const Size(0, 30),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: busy ? null : () => quick(minutes),
                              child: Text(
                                minutes == 60
                                    ? t('1小时后', 'In 1 hour')
                                    : t('$minutes分钟后', 'In $minutes min'),
                                style: const TextStyle(fontSize: 12),
                                maxLines: 2,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    ),
                    DropdownButtonFormField<String>(
                      key: ValueKey('reminder-mode-$mode'),
                      initialValue: mode,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: t('提醒方式', 'Repeat'),
                        isDense: true,
                      ),
                      items: [
                        for (final item in [
                          ('once', t('提醒一次', 'Once')),
                          ('repeat', t('每10分钟', 'Every 10 minutes')),
                          ('daily', t('每天重复', 'Daily')),
                        ])
                          DropdownMenuItem(
                            value: item.$1,
                            child: Text(
                              item.$2,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                      ],
                      onChanged: busy
                          ? null
                          : (value) => setState(() => mode = value!),
                    ),
                    if (mode == 'daily')
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: TextFormField(
                          key: const ValueKey('reminder-until'),
                          controller: until,
                          enabled: !busy,
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            labelText: t('结束日期（含当天）', 'End date (inclusive)'),
                            hintText: 'YYYY-MM-DD',
                            isDense: true,
                          ),
                          validator: (value) => parseDate(value ?? '') == null
                              ? t('格式：年-月-日', 'Use YYYY-MM-DD')
                              : null,
                        ),
                      ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          error!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFFA53832),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (widget.note.nextAlertAt != null)
                  Expanded(
                    child: TextButton(
                      onPressed: busy ? null : () => run(widget.onCancel),
                      child: Text(
                        t('取消提醒', 'Remove reminder'),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                FilledButton(
                  key: const ValueKey('save-reminder'),
                  onPressed: busy ? null : save,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(80, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(busy ? t('保存中', 'Saving') : t('保存', 'Save')),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
