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
  int? quickMinutes;
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
      quickMinutes = minutes;
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

  void manualEdit(String _) {
    if (quickMinutes != null || error != null) {
      setState(() {
        quickMinutes = null;
        error = null;
      });
    }
  }

  Color get fieldColor => Color.alphaBlend(
    Colors.white.withValues(alpha: .45),
    Theme.of(context).colorScheme.surface,
  );

  InputDecoration fieldDecoration(String label, {String? hint}) {
    final colors = Theme.of(context).colorScheme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: BorderSide(
        color: colors.outlineVariant.withValues(alpha: .65),
      ),
    );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: fieldColor,
      isDense: true,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      labelStyle: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: colors.primary, width: 1.5),
      ),
      errorMaxLines: 2,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: 270,
      height: 250,
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
          child: Column(
            children: [
              SizedBox(
                height: 36,
                child: Row(
                  children: [
                    IconButton(
                      tooltip: t('返回便利贴', 'Back to note'),
                      onPressed: busy ? null : widget.onBack,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      style: IconButton.styleFrom(
                        backgroundColor: fieldColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11),
                        ),
                      ),
                      icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        t('设置提醒', 'Set reminder'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.notifications_active_outlined,
                      size: 18,
                      color: colors.primary,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Form(
                  key: form,
                  child: ListView(
                    padding: EdgeInsets.only(
                      top: mode == 'daily' ? 6 : 12,
                      bottom: 2,
                    ),
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
                              onChanged: manualEdit,
                              style: const TextStyle(fontSize: 13),
                              keyboardType: TextInputType.datetime,
                              textInputAction: TextInputAction.next,
                              decoration: fieldDecoration(
                                t('日期', 'Date'),
                                hint: 'YYYY-MM-DD',
                              ),
                              validator: (value) =>
                                  parseDate(value ?? '') == null
                                  ? t('格式：年-月-日', 'Use YYYY-MM-DD')
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              key: const ValueKey('reminder-time'),
                              controller: time,
                              enabled: !busy,
                              onChanged: manualEdit,
                              style: const TextStyle(fontSize: 13),
                              keyboardType: TextInputType.datetime,
                              textInputAction: TextInputAction.done,
                              decoration: fieldDecoration(
                                t('24小时制', '24-hour time'),
                                hint: 'HH:mm',
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
                      if (mode != 'daily') ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            for (final minutes in [10, 30, 60]) ...[
                              if (minutes != 10) const SizedBox(width: 6),
                              Expanded(
                                child: Semantics(
                                  selected: quickMinutes == minutes,
                                  child: TextButton(
                                    key: ValueKey('quick-reminder-$minutes'),
                                    style: TextButton.styleFrom(
                                      minimumSize: const Size(0, 30),
                                      backgroundColor: Color.alphaBlend(
                                        colors.primary.withValues(
                                          alpha: quickMinutes == minutes
                                              ? .16
                                              : .06,
                                        ),
                                        colors.surface,
                                      ),
                                      side: BorderSide(
                                        color: quickMinutes == minutes
                                            ? colors.primary.withValues(
                                                alpha: .45,
                                              )
                                            : Colors.transparent,
                                      ),
                                      shape: const StadiumBorder(),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                      ),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    onPressed: busy
                                        ? null
                                        : () => quick(minutes),
                                    child: Text(
                                      minutes == 60
                                          ? t('1小时后', 'In 1 hour')
                                          : t('$minutes分钟后', 'In $minutes min'),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: quickMinutes == minutes
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                      ),
                                      maxLines: 2,
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                      ] else
                        const SizedBox(height: 4),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 4, bottom: 3),
                            child: Text(
                              t('提醒方式', 'Repeat'),
                              style: TextStyle(
                                fontSize: 10,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: fieldColor,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: colors.outlineVariant.withValues(
                                  alpha: .65,
                                ),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(3),
                              child: Row(
                                children: [
                                  for (final item in [
                                    ('once', t('提醒一次', 'Once')),
                                    ('repeat', t('每10分钟', '10 min')),
                                    ('daily', t('每天重复', 'Daily')),
                                  ])
                                    Expanded(
                                      child: Semantics(
                                        selected: mode == item.$1,
                                        child: TextButton(
                                          key: ValueKey(
                                            'reminder-mode-${item.$1}',
                                          ),
                                          onPressed: busy
                                              ? null
                                              : () => setState(() {
                                                  mode = item.$1;
                                                  error = null;
                                                }),
                                          style: TextButton.styleFrom(
                                            foregroundColor: mode == item.$1
                                                ? colors.onPrimary
                                                : colors.onSurfaceVariant,
                                            backgroundColor: mode == item.$1
                                                ? colors.primary
                                                : Colors.transparent,
                                            minimumSize: const Size(0, 32),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 2,
                                              vertical: 6,
                                            ),
                                            tapTargetSize: MaterialTapTargetSize
                                                .shrinkWrap,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(11),
                                            ),
                                          ),
                                          child: Text(
                                            item.$2,
                                            textAlign: TextAlign.center,
                                            maxLines: 2,
                                            style: const TextStyle(
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (mode == 'daily')
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: TextFormField(
                            key: const ValueKey('reminder-until'),
                            controller: until,
                            enabled: !busy,
                            onChanged: (_) {
                              if (error != null) setState(() => error = null);
                            },
                            style: const TextStyle(fontSize: 13),
                            keyboardType: TextInputType.datetime,
                            decoration: fieldDecoration(
                              t('结束日期（含当天）', 'End date (inclusive)'),
                              hint: 'YYYY-MM-DD',
                            ),
                            validator: (value) => parseDate(value ?? '') == null
                                ? t('格式：年-月-日', 'Use YYYY-MM-DD')
                                : null,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    error!,
                    style: TextStyle(fontSize: 11, color: colors.error),
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (widget.note.nextAlertAt != null) ...[
                    Expanded(
                      child: TextButton(
                        onPressed: busy ? null : () => run(widget.onCancel),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 34),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          t('取消提醒', 'Remove reminder'),
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: FilledButton.icon(
                      key: const ValueKey('save-reminder'),
                      onPressed: busy ? null : save,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 34),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: busy
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colors.onPrimary,
                              ),
                            )
                          : const Icon(Icons.check_rounded, size: 17),
                      label: Text(
                        busy ? t('保存中', 'Saving') : t('保存', 'Save'),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
