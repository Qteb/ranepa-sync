package com.qteb.ranepa_timetable

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

private data class LessonItem(val start: Long, val end: Long, val title: String, val room: String)

/// Пары пишет Flutter-приложение (home_widget). Прошедшие отбрасываются здесь,
/// при каждом обновлении виджета (раз в 30 минут), без запуска приложения.
class RanepaWidgetProvider : HomeWidgetProvider() {
    private val rowIds = listOf(
        Triple(R.id.row1, R.id.row1_title, R.id.row1_sub),
        Triple(R.id.row2, R.id.row2_title, R.id.row2_sub),
        Triple(R.id.row3, R.id.row3_title, R.id.row3_sub),
        Triple(R.id.row4, R.id.row4_title, R.id.row4_sub),
    )

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val now = System.currentTimeMillis() / 1000
        val upcoming = parse(widgetData.getString("lessons", null)).filter { it.end > now }
        val dayLessons = upcoming.firstOrNull()?.let { first ->
            upcoming.filter { sameDay(it.start, first.start) }
        } ?: emptyList()

        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.ranepa_widget)
            views.setOnClickPendingIntent(
                R.id.widget_root,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
            )
            views.setTextViewText(
                R.id.widget_title,
                dayLessons.firstOrNull()?.let { dayLabel(it.start) } ?: "Расписание",
            )
            views.setViewVisibility(R.id.widget_empty, if (dayLessons.isEmpty()) View.VISIBLE else View.GONE)
            rowIds.forEachIndexed { i, (row, title, sub) ->
                val lesson = dayLessons.getOrNull(i)
                views.setViewVisibility(row, if (lesson == null) View.GONE else View.VISIBLE)
                if (lesson != null) {
                    views.setTextViewText(title, lesson.title)
                    val room = if (lesson.room.isEmpty()) "" else " · ${lesson.room}"
                    views.setTextViewText(sub, "${hm(lesson.start)}–${hm(lesson.end)}$room")
                }
            }
            val more = dayLessons.size - rowIds.size
            views.setViewVisibility(R.id.widget_more, if (more > 0) View.VISIBLE else View.GONE)
            views.setTextViewText(R.id.widget_more, "ещё $more")
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    private fun parse(raw: String?): List<LessonItem> {
        if (raw.isNullOrEmpty()) return emptyList()
        val arr = JSONArray(raw)
        return (0 until arr.length()).map {
            val o = arr.getJSONObject(it)
            LessonItem(o.getLong("s"), o.getLong("e"), o.getString("t"), o.optString("r"))
        }.sortedBy { it.start }
    }

    private fun calendarAt(seconds: Long) = Calendar.getInstance().apply { timeInMillis = seconds * 1000 }

    private fun sameDay(a: Long, b: Long): Boolean {
        val ca = calendarAt(a)
        val cb = calendarAt(b)
        return ca.get(Calendar.YEAR) == cb.get(Calendar.YEAR) &&
            ca.get(Calendar.DAY_OF_YEAR) == cb.get(Calendar.DAY_OF_YEAR)
    }

    private fun hm(seconds: Long) = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(seconds * 1000))

    private fun dayLabel(seconds: Long): String {
        val now = System.currentTimeMillis() / 1000
        return when {
            sameDay(seconds, now) -> "Сегодня"
            sameDay(seconds, now + 86_400) -> "Завтра"
            else -> SimpleDateFormat("EE, d MMMM", Locale("ru")).format(Date(seconds * 1000))
                .replaceFirstChar { it.uppercase() }
        }
    }
}
