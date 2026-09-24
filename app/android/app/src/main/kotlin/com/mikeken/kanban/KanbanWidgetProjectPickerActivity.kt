package com.mikeken.kanban

import android.app.Activity
import android.app.AlertDialog
import android.appwidget.AppWidgetManager
import android.os.Bundle

class KanbanWidgetProjectPickerActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val widgetId = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, -1)
        if (widgetId < 0) {
            finish()
            return
        }
        val store = KanbanWidgetStore(this)
        val projects = store.loadProjects()
        if (projects.isEmpty()) {
            AlertDialog.Builder(this)
                .setMessage(R.string.widget_no_projects)
                .setPositiveButton(android.R.string.ok) { _, _ -> finish() }
                .setOnCancelListener { finish() }
                .show()
            return
        }
        val selectedId = store.selectedProjectId(widgetId)
        val selectedIndex = projects.indexOfFirst { it.id == selectedId }
        val labels = Array<CharSequence>(projects.size) { projects[it].title }
        AlertDialog.Builder(this)
            .setTitle(R.string.widget_choose_project)
            .setSingleChoiceItems(
                labels,
                selectedIndex,
            ) { dialog, index ->
                store.selectProject(widgetId, projects[index].id)
                KanbanHomeWidgetProvider.updateAll(this)
                dialog.dismiss()
                finish()
            }
            .setNegativeButton(android.R.string.cancel) { _, _ -> finish() }
            .setOnCancelListener { finish() }
            .show()
    }
}
