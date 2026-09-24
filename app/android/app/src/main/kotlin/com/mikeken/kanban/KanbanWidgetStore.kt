package com.mikeken.kanban

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

data class KanbanWidgetCardItem(
    val title: String,
    val badge: String,
)

data class KanbanWidgetProject(
    val id: String,
    val title: String,
    val snapshot: KanbanWidgetSnapshot,
)

data class KanbanWidgetSnapshot(
    val projectName: String,
    val overdueCount: Int,
    val todayCount: Int,
    val todoCount: Int,
    val items: List<KanbanWidgetCardItem>,
) {
    val isEmpty: Boolean
        get() = overdueCount == 0 && todayCount == 0 && todoCount == 0 && items.isEmpty()

    fun summaryText(): String {
        return "Overdue $overdueCount · Today $todayCount · To Do $todoCount"
    }
}

class KanbanWidgetStore(context: Context) {
    private val prefs =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun saveProjects(json: String) {
        JSONObject(json)
        prefs.edit().putString(KEY_PROJECTS, json).apply()
    }

    fun loadProjects(): List<KanbanWidgetProject> {
        val raw = prefs.getString(KEY_PROJECTS, null) ?: return emptyList()
        return try {
            val projects = JSONObject(raw).optJSONArray("projects") ?: return emptyList()
            buildList {
                for (index in 0 until projects.length()) {
                    val project = projects.optJSONObject(index) ?: continue
                    val id = project.optString("id")
                    val snapshotJson = project.optJSONObject("snapshot") ?: continue
                    val snapshot = parseSnapshot(snapshotJson) ?: continue
                    if (id.isBlank()) continue
                    add(KanbanWidgetProject(id, project.optString("title"), snapshot))
                }
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun loadSnapshot(appWidgetId: Int): KanbanWidgetSnapshot? {
        val projects = loadProjects()
        if (prefs.contains(KEY_PROJECTS)) {
            if (projects.isEmpty()) return null
            val selectedId = prefs.getString("$KEY_SELECTED_PREFIX$appWidgetId", null)
                ?: loadActiveProjectId()
            return projects.firstOrNull { it.id == selectedId }?.snapshot
                ?: projects.first().snapshot
        }
        val raw = prefs.getString(KEY_SNAPSHOT, null) ?: return null
        return try {
            parseSnapshot(JSONObject(raw))
        } catch (_: Exception) {
            null
        }
    }

    fun selectedProjectId(appWidgetId: Int): String? =
        prefs.getString("$KEY_SELECTED_PREFIX$appWidgetId", null) ?: loadActiveProjectId()

    fun selectProject(appWidgetId: Int, projectId: String) {
        prefs.edit().putString("$KEY_SELECTED_PREFIX$appWidgetId", projectId).apply()
    }

    fun deleteWidget(appWidgetId: Int) {
        prefs.edit().remove("$KEY_SELECTED_PREFIX$appWidgetId").apply()
    }

    private fun loadActiveProjectId(): String? {
        val raw = prefs.getString(KEY_PROJECTS, null) ?: return null
        return try {
            JSONObject(raw).optString("activeProjectId").ifBlank { null }
        } catch (_: Exception) {
            null
        }
    }

    companion object {
        const val PREFS_NAME = "kanban_home_widget"
        private const val KEY_SNAPSHOT = "snapshot"
        private const val KEY_PROJECTS = "projects"
        private const val KEY_SELECTED_PREFIX = "selected_"

        fun parseSnapshot(json: JSONObject): KanbanWidgetSnapshot? {
            return try {
                val items = mutableListOf<KanbanWidgetCardItem>()
                val array = json.optJSONArray("items") ?: JSONArray()
                for (index in 0 until array.length()) {
                    val item = array.optJSONObject(index) ?: continue
                    val title = item.optString("title").trim()
                    if (title.isEmpty()) continue
                    items.add(
                        KanbanWidgetCardItem(
                            title = title,
                            badge = when (val badge = item.optString("badge", "To Do")) {
                                "逾期" -> "Overdue"
                                "今日" -> "Today"
                                "返工" -> "Rework"
                                "待办" -> "To Do"
                                else -> badge
                            },
                        ),
                    )
                }
                KanbanWidgetSnapshot(
                    projectName = json.optString("projectName", "Kanban"),
                    overdueCount = json.optInt("overdueCount", 0),
                    todayCount = json.optInt("todayCount", 0),
                    todoCount = json.optInt("todoCount", 0),
                    items = items,
                )
            } catch (_: Exception) {
                null
            }
        }
    }
}
