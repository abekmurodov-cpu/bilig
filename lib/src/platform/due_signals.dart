import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';

import '../l10n/app_strings.dart';
import '../models/knowledge_item.dart';
import '../ui/widgets/category_tree.dart';
import '../ui/widgets/tree_model.dart';

/// Shows how much is due outside the app, as a reminder without a
/// notification: a badge on the Dock icon (macOS) and the home-screen widget
/// with the student's biggest tree (Android).
class DueSignals {
  static const _badge = MethodChannel('bilig/badge');

  /// Due times further ahead than this aren't handed to the widget.
  static const _horizon = Duration(days: 60);
  static const _maxTimes = 800;

  static bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static bool get _mac => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  static Future<void> update(List<KnowledgeItem> notes, AppStrings strings) async {
    final now = DateTime.now();
    final due = notes.where((n) => n.isDue(now)).length;
    try {
      if (_mac) await _badge.invokeMethod('set', due);
      if (_android) await _updateWidget(notes, strings, now);
    } on MissingPluginException {
      // Not available here (tests, other platforms).
    } on PlatformException {
      // A badge or widget is a nicety; never let it break the app.
    }
  }

  /// A dark or light Dock icon to match the app's theme (macOS).
  static Future<void> setDarkIcon(bool dark) async {
    if (!_mac) return;
    try {
      await _badge.invokeMethod('icon', dark);
    } on MissingPluginException {
      // Not available here (tests).
    } on PlatformException {
      // A nicety; never let it break the app.
    }
  }

  static Future<void> _updateWidget(
      List<KnowledgeItem> notes, AppStrings strings, DateTime now) async {
    final limit = now.add(_horizon);
    final times = [
      for (final n in notes)
        if (n.dueDate.isBefore(limit)) n.dueDate.millisecondsSinceEpoch,
    ]..sort();
    await HomeWidget.saveWidgetData<String>(
        'dueAt', times.take(_maxTimes).join(','));
    await HomeWidget.saveWidgetData<String>('labelDue', strings.widgetDue);
    await HomeWidget.saveWidgetData<String>('labelNone', strings.allCaughtUp);

    // The biggest category's tree, drawn still.
    final groups = <String, List<KnowledgeItem>>{};
    for (final n in notes) {
      (groups[n.category?.trim().isNotEmpty == true ? n.category!.trim() : ''] ??= [])
          .add(n);
    }
    if (groups.isNotEmpty) {
      final biggest = groups.entries.reduce((a, b) => a.value.length >= b.value.length ? a : b);
      final ordered = leafOrder(biggest.value);
      final model = TreeModel.generate(count: ordered.length, seed: biggest.key);
      final side = math.min(220.0, math.max(model.size.width, model.size.height));
      await HomeWidget.renderFlutterWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: FittedBox(child: TreeCanvas(model: model, notes: ordered, still: true)),
        ),
        key: 'tree',
        logicalSize: Size(side, side),
      );
    }
    await HomeWidget.updateWidget(androidName: 'BiligWidgetProvider');
  }
}
