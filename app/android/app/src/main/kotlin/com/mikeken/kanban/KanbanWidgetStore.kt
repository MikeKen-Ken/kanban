package com.mikeken.kanban

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

data class KanbanWidgetCardItem(
    val title: String,
    val badge: String,
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
        return "逾期 $overdueCount · 今日 $todayCount · 待办 $todoCount"
    }
}

class KanbanWidgetStore(context: Context) {
    private val prefs =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun saveSnapshot(json: String) {
        prefs.edit().putString(KEY_SNAPSHOT, json).apply()
    }

    fun loadSnapshot(): KanbanWidgetSnapshot? {
        val raw = prefs.getString(KEY_SNAPSHOT, null) ?: return null
        return parseSnapshot(raw)
    }

    companion object {
        const val PREFS_NAME = "kanban_home_widget"
        private const val KEY_SNAPSHOT = "snapshot"

        fun parseSnapshot(raw: String): KanbanWidgetSnapshot? {
            return try {
                val json = JSONObject(raw)
                val items = mutableListOf<KanbanWidgetCardItem>()
                val array = json.optJSONArray("items") ?: JSONArray()
                for (index in 0 until array.length()) {
                    val item = array.optJSONObject(index) ?: continue
                    val title = item.optString("title").trim()
                    if (title.isEmpty()) continue
                    items.add(
                        KanbanWidgetCardItem(
                            title = title,
                            badge = item.optString("badge", "待办"),
                        ),
                    )
                }
                KanbanWidgetSnapshot(
                    projectName = json.optString("projectName", "看板"),
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
