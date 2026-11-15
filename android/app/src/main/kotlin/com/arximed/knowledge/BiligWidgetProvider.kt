package com.arximed.knowledge

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.io.File

/**
 * Home-screen widget: the student's tree and how many notes are due. The app
 * saves the due times of upcoming notes, so the count stays right as the day
 * goes on even when the app isn't opened.
 */
class BiligWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val now = System.currentTimeMillis()
        val dueAt = widgetData.getString("dueAt", "") ?: ""
        val due = dueAt.split(',').count { it.isNotBlank() && (it.toLongOrNull() ?: Long.MAX_VALUE) <= now }
        val label = if (due > 0) widgetData.getString("labelDue", "to review")
        else widgetData.getString("labelNone", "All caught up")
        val tree = widgetData.getString("tree", null)?.let { File(it) }?.takeIf { it.exists() }

        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.bilig_widget).apply {
                setTextViewText(R.id.widget_count, if (due > 0) due.toString() else "✓")
                setTextViewText(R.id.widget_label, label)
                if (tree != null) {
                    setImageViewBitmap(R.id.widget_tree, BitmapFactory.decodeFile(tree.absolutePath))
                    setViewVisibility(R.id.widget_tree, View.VISIBLE)
                } else {
                    setViewVisibility(R.id.widget_tree, View.GONE)
                }
                setOnClickPendingIntent(
                    R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
                )
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
