package com.mikeken.kanban

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews

class KanbanHomeWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onEnabled(context: Context) {
        updateAll(context)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        val store = KanbanWidgetStore(context)
        for (id in appWidgetIds) store.deleteWidget(id)
    }

    companion object {
        private val itemViewIds = intArrayOf(
            R.id.widget_item_1,
            R.id.widget_item_2,
            R.id.widget_item_3,
            R.id.widget_item_4,
            R.id.widget_item_5,
        )

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, KanbanHomeWidgetProvider::class.java)
            val ids = manager.getAppWidgetIds(component)
            for (id in ids) {
                updateAppWidget(context, manager, id)
            }
        }

        private fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
        ) {
            val views = RemoteViews(context.packageName, R.layout.widget_kanban)
            val snapshot = KanbanWidgetStore(context).loadSnapshot(appWidgetId)
            val launchIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingIntent = PendingIntent.getActivity(
                context,
                appWidgetId,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
            val pickerIntent = Intent(context, KanbanWidgetProjectPickerActivity::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
            }
            views.setOnClickPendingIntent(
                R.id.widget_project_picker,
                PendingIntent.getActivity(
                    context,
                    appWidgetId,
                    pickerIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                ),
            )
            val syncIntent = Intent(context, MainActivity::class.java).apply {
                action = MainActivity.ACTION_WIDGET_SYNC
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            views.setOnClickPendingIntent(
                R.id.widget_sync,
                PendingIntent.getActivity(
                    context,
                    appWidgetId,
                    syncIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                ),
            )

            if (snapshot == null) {
                views.setTextViewText(R.id.widget_project_name, context.getString(R.string.widget_default_title))
                views.setTextViewText(R.id.widget_summary, context.getString(R.string.widget_sync_hint))
                views.setViewVisibility(R.id.widget_empty_message, View.VISIBLE)
                views.setTextViewText(R.id.widget_empty_message, context.getString(R.string.widget_no_data))
                for (viewId in itemViewIds) {
                    views.setViewVisibility(viewId, View.GONE)
                }
            } else {
                views.setTextViewText(R.id.widget_project_name, snapshot.projectName)
                views.setTextViewText(R.id.widget_summary, snapshot.summaryText())
                if (snapshot.items.isEmpty()) {
                    views.setViewVisibility(R.id.widget_empty_message, View.VISIBLE)
                    views.setTextViewText(
                        R.id.widget_empty_message,
                        if (snapshot.isEmpty) context.getString(R.string.widget_no_todos)
                        else context.getString(R.string.widget_no_items),
                    )
                } else {
                    views.setViewVisibility(R.id.widget_empty_message, View.GONE)
                }
                for (index in itemViewIds.indices) {
                    val viewId = itemViewIds[index]
                    val item = snapshot.items.getOrNull(index)
                    if (item == null) {
                        views.setViewVisibility(viewId, View.GONE)
                        continue
                    }
                    views.setViewVisibility(viewId, View.VISIBLE)
                    views.setTextViewText(viewId, "${item.badge} · ${item.title}")
                }
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
