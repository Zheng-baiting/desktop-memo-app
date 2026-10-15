part of 'main.dart';

class ReminderActions extends StatefulWidget {
  const ReminderActions({
    super.key,
    required this.daily,
    required this.onAction,
  });

  final bool daily;
  final Future<void> Function(int? minutes) onAction;

  @override
  State<ReminderActions> createState() => _ReminderActionsState();
}

class _ReminderActionsState extends State<ReminderActions> {
  bool _pending = false;
  bool _failed = false;

  Future<void> _act(int? minutes) async {
    if (_pending) return;
    setState(() {
      _pending = true;
      _failed = false;
    });
    try {
      await widget.onAction(minutes);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  Widget _button(String label, int? minutes) => TextButton(
    onPressed: _pending ? null : () => _act(minutes),
    style: TextButton.styleFrom(
      foregroundColor: memoPaper,
      disabledForegroundColor: memoPaper.withValues(alpha: 0.55),
      minimumSize: const Size(0, 36),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: Theme.of(context).textTheme.labelLarge
          ?.copyWith(fontSize: 12, height: 1.2),
    ),
    child: Text(label, textAlign: TextAlign.center, maxLines: 2),
  );

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 260),
    child: Material(
      color: memoAccent,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: _button(uiText(context, '10分钟后', 'In 10 min'), 10),
                ),
                Expanded(
                  child: _button(uiText(context, '30分钟后', 'In 30 min'), 30),
                ),
              ],
            ),
            _button(
              widget.daily
                  ? uiText(
                      context,
                      '今天已读 · 保留每天提醒',
                      'Done today · keep daily reminder',
                    )
                  : uiText(context, '我知道了，停止提醒', 'Dismiss and stop reminder'),
              null,
            ),
            if (_pending || _failed)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  _pending
                      ? uiText(context, '正在处理…', 'Working…')
                      : uiText(
                          context,
                          '操作失败，请重试',
                          'Could not complete. Try again.',
                        ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: memoPaper,
                    fontSize: 10,
                    height: 1.2,
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
