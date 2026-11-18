import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';

/// iOS-style pieces the app uses on every platform: switches, segmented
/// controls, alerts, action sheets and wheel pickers.

/// A list row with an iOS switch at the end; tapping the row flips it.
class IosSwitchTile extends StatelessWidget {
  const IosSwitchTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.leading,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: leading,
        title: title,
        subtitle: subtitle,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        trailing: CupertinoSwitch(
          value: value,
          activeTrackColor: Theme.of(context).colorScheme.primary,
          onChanged: onChanged,
        ),
      );
}

/// An iOS segmented control. [onChanged] null disables it.
class IosSegmented<T extends Object> extends StatelessWidget {
  const IosSegmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.expand = true,
  });

  /// Fills the width; off for a compact control in a toolbar.
  final bool expand;

  /// Each value's label, optionally with an icon.
  final Map<T, (IconData?, String)> segments;
  final T value;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Opacity(
      opacity: onChanged == null ? 0.5 : 1,
      child: IgnorePointer(
        ignoring: onChanged == null,
        child: SizedBox(
          width: expand ? double.infinity : null,
          child: CupertinoSlidingSegmentedControl<T>(
            groupValue: value,
            backgroundColor: scheme.surfaceContainerHighest,
            thumbColor: dark ? scheme.surfaceBright : Colors.white,
            padding: const EdgeInsets.all(3),
            onValueChanged: (v) {
              if (v != null) onChanged?.call(v);
            },
            children: {
              for (final MapEntry(:key, value: (icon, label)) in segments.entries)
                key: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: 16, color: scheme.onSurface),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(label,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight:
                                    key == value ? FontWeight.w600 : FontWeight.w500,
                                color: scheme.onSurface)),
                      ),
                    ],
                  ),
                ),
            },
          ),
        ),
      ),
    );
  }
}

/// An iOS alert asking to confirm; true when confirmed.
Future<bool> showIosConfirm(
  BuildContext context, {
  required String title,
  String? message,
  required String confirm,
  bool destructive = false,
}) async {
  final ok = await showCupertinoDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (context) => CupertinoAlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(context, false),
          child: Text(context.s.cancel),
        ),
        CupertinoDialogAction(
          isDefaultAction: !destructive,
          isDestructiveAction: destructive,
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return ok == true;
}

/// An iOS alert with one text field; the typed text, or null if cancelled.
Future<String?> showIosPrompt(
  BuildContext context, {
  required String title,
  String? message,
  String initial = '',
  required String confirm,
  bool autocorrect = true,
}) async {
  final controller = TextEditingController(text: initial);
  final text = await showCupertinoDialog<String>(
    context: context,
    barrierDismissible: true,
    builder: (context) => CupertinoAlertDialog(
      title: Text(title),
      content: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(message),
              ),
            CupertinoTextField(
              controller: controller,
              autofocus: true,
              autocorrect: autocorrect,
              clearButtonMode: OverlayVisibilityMode.editing,
              onSubmitted: (v) => Navigator.pop(context, v),
            ),
          ],
        ),
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(context),
          child: Text(context.s.cancel),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(context, controller.text),
          child: Text(confirm),
        ),
      ],
    ),
  );
  controller.dispose();
  return text;
}

/// An iOS action sheet; the chosen option's value, or null if cancelled.
Future<T?> showIosActionSheet<T>(
  BuildContext context, {
  String? title,
  required List<(IconData, String, T)> options,
}) =>
    showCupertinoModalPopup<T>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: title == null ? null : Text(title),
        actions: [
          for (final (icon, label, value) in options)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, value),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 22),
                  const SizedBox(width: 10),
                  Text(label),
                ],
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(context),
          child: Text(context.s.cancel),
        ),
      ),
    );

/// The wheel picker in a bottom popup with Cancel and Done.
Future<DateTime?> _showWheel(
  BuildContext context, {
  required CupertinoDatePickerMode mode,
  required DateTime initial,
  DateTime? minimum,
  DateTime? maximum,
}) {
  var picked = initial;
  final strings = context.s;
  return showCupertinoModalPopup<DateTime>(
    context: context,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  CupertinoButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(strings.cancel),
                  ),
                  const Spacer(),
                  CupertinoButton(
                    onPressed: () => Navigator.pop(context, picked),
                    child: Text(strings.done,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              SizedBox(
                height: 216,
                child: CupertinoTheme(
                  data: CupertinoThemeData(
                    brightness: Theme.of(context).brightness,
                    primaryColor: scheme.primary,
                  ),
                  child: CupertinoDatePicker(
                    mode: mode,
                    initialDateTime: initial,
                    minimumDate: minimum,
                    maximumDate: maximum,
                    use24hFormat: MediaQuery.alwaysUse24HourFormatOf(context),
                    onDateTimeChanged: (v) => picked = v,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// An iOS time wheel.
Future<TimeOfDay?> showIosTimePicker(BuildContext context, TimeOfDay initial) async {
  final now = DateTime.now();
  final picked = await _showWheel(
    context,
    mode: CupertinoDatePickerMode.time,
    initial: DateTime(now.year, now.month, now.day, initial.hour, initial.minute),
  );
  return picked == null ? null : TimeOfDay.fromDateTime(picked);
}

/// An iOS date wheel.
Future<DateTime?> showIosDatePicker(
  BuildContext context, {
  required DateTime initial,
  required DateTime first,
  required DateTime last,
}) =>
    _showWheel(
      context,
      mode: CupertinoDatePickerMode.date,
      initial: initial,
      minimum: DateTime(first.year, first.month, first.day),
      maximum: last,
    );
