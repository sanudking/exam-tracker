package com.example.exam_tracker

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider

class ExamTrackerWidgetProvider : HomeWidgetProvider() {

    // ── Phase enum matching the app's _ExamPhase ────────────────────────
    private enum class Phase { FUTURE, LIVE, PAST, DONE }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_WIDGET_TICK) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val ids = appWidgetManager.getAppWidgetIds(
                ComponentName(context, ExamTrackerWidgetProvider::class.java)
            )
            if (ids.isNotEmpty()) {
                onUpdate(context, appWidgetManager, ids, HomeWidgetPlugin.getData(context))
            }
        }
    }

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        scheduleTicker(context)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        cancelTicker(context)
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        scheduleTicker(context)

        appWidgetIds.forEach { widgetId ->
            // ── Strict per-widget keys ──────────────────────────────
            val title = widgetData.getString("widget_exam_title_$widgetId", null)
            val date = widgetData.getString("widget_exam_date_$widgetId", null)
            val epochMs = widgetData.getLong("widget_exam_epoch_ms_$widgetId", 0L)
            val durationHrs = getWidgetInt(widgetData, widgetId, "widget_exam_duration_hrs", 3)
            val isCompleted = widgetData.getBoolean("widget_exam_completed_$widgetId", false)

            val views = RemoteViews(context.packageName, R.layout.exam_tracker_widget)

            if (title == null) {
                // ── Empty state ─────────────────────────────────────
                views.setViewVisibility(R.id.widget_content_layout, View.GONE)
                views.setViewVisibility(R.id.widget_empty_layout, View.VISIBLE)
            } else {
                views.setViewVisibility(R.id.widget_content_layout, View.VISIBLE)
                views.setViewVisibility(R.id.widget_empty_layout, View.GONE)

                // ── Determine phase (mirrors app's _phaseForExam) ───
                val now = System.currentTimeMillis()
                val phase = determinePhase(epochMs, durationHrs, isCompleted, now)

                // ── Schedule a precise update at the exact start time ──
                if (epochMs > now) {
                    schedulePreciseUpdate(context, epochMs)
                }

                // ── Title ───────────────────────────────────────────
                views.setTextViewText(R.id.widget_exam_title, title)

                // ── Date (same format as app: "DD Mon YYYY at H:MM AM/PM") ──
                views.setTextViewText(R.id.widget_exam_date, date ?: "")

                // ── Countdown / Status text ─────────────────────────
                when (phase) {
                    Phase.DONE, Phase.PAST -> {
                        views.setViewVisibility(R.id.widget_exam_chronometer, View.GONE)
                        views.setViewVisibility(R.id.widget_exam_countdown, View.VISIBLE)
                        views.setTextViewText(R.id.widget_exam_countdown, "✓ DONE")
                    }
                    Phase.LIVE -> {
                        views.setViewVisibility(R.id.widget_exam_chronometer, View.GONE)
                        views.setViewVisibility(R.id.widget_exam_countdown, View.VISIBLE)
                        views.setTextViewText(R.id.widget_exam_countdown, "🔴 LIVE NOW")
                    }
                    Phase.FUTURE -> {
                        val diffMs = epochMs - now
                        // If we are within 2 seconds of start, just show LIVE NOW to avoid negative/zero flicker
                        if (diffMs < 1500L) {
                            views.setViewVisibility(R.id.widget_exam_chronometer, View.GONE)
                            views.setViewVisibility(R.id.widget_exam_countdown, View.VISIBLE)
                            views.setTextViewText(R.id.widget_exam_countdown, "🔴 LIVE NOW")
                        } else {
                            val countdownText = buildFutureCountdown(diffMs)
                            if (countdownText.useChronometer &&
                                Build.VERSION.SDK_INT >= Build.VERSION_CODES.N
                            ) {
                                val base = SystemClock.elapsedRealtime() + diffMs
                                views.setViewVisibility(R.id.widget_exam_chronometer, View.VISIBLE)
                                views.setViewVisibility(R.id.widget_exam_countdown, View.GONE)
                                views.setChronometer(
                                    R.id.widget_exam_chronometer, base, "%s left", true
                                )
                                views.setChronometerCountDown(R.id.widget_exam_chronometer, true)
                            } else {
                                views.setViewVisibility(R.id.widget_exam_chronometer, View.GONE)
                                views.setViewVisibility(R.id.widget_exam_countdown, View.VISIBLE)
                                views.setTextViewText(R.id.widget_exam_countdown, countdownText.text)
                            }
                        }
                    }
                }

                // ── Grey-out for PAST / DONE (match app's 0.45 opacity) ──
                val isFaded = phase == Phase.PAST || phase == Phase.DONE
                val titleColor = if (isFaded) 0x73FFFFFF.toInt() else 0xFFFFFFFF.toInt()
                val dateColor = if (isFaded) 0x73CBD5E1.toInt() else 0xFFCBD5E1.toInt()
                val countdownColor = if (isFaded) 0x73FDBA74.toInt() else 0xFFFDBA74.toInt()
                val labelColor = if (isFaded) 0x7393C5FD.toInt() else 0xFF93C5FD.toInt()

                views.setTextColor(R.id.widget_exam_title, titleColor)
                views.setTextColor(R.id.widget_exam_date, dateColor)
                views.setTextColor(R.id.widget_exam_countdown, countdownColor)
                views.setTextColor(R.id.widget_exam_chronometer, countdownColor)
                views.setTextColor(R.id.widget_label, labelColor)
            }

            val launchIntent = HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java
            )
            views.setOnClickPendingIntent(R.id.widget_root, launchIntent)
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    // ── Phase determination (mirrors app's _phaseForExam) ───────────────
    private fun determinePhase(
        epochMs: Long,
        durationHrs: Int,
        isCompleted: Boolean,
        now: Long,
    ): Phase {
        if (isCompleted) return Phase.DONE
        // Switch to LIVE slightly proactively to prevent negative flicker
        if (now < epochMs - 800L) return Phase.FUTURE
        val examEndMs = epochMs + durationHrs * 3600_000L
        if (now <= examEndMs) return Phase.LIVE
        return Phase.PAST
    }

    // ── Countdown text (mirrors app's _futureCountdownText) ────────────
    private data class CountdownResult(val text: String, val useChronometer: Boolean)

    private fun buildFutureCountdown(diffMs: Long): CountdownResult {
        val totalSeconds = diffMs / 1000L
        if (totalSeconds <= 0) return CountdownResult("Now", false)

        val totalHours = totalSeconds / 3600L

        // < 24 hours → use live Chronometer
        if (totalHours < 24) {
            val hrs = totalHours
            val mins = (totalSeconds % 3600L) / 60L
            val secs = totalSeconds % 60L
            val parts = mutableListOf<String>()
            if (hrs > 0) parts.add("$hrs Hr")
            if (mins > 0) parts.add("$mins Min")
            if (secs > 0 || parts.isEmpty()) parts.add("$secs Sec")
            return CountdownResult("${parts.joinToString(" ")} left", true)
        }

        val days = totalHours / 24L

        // < 30 days
        if (days < 30) {
            val remHrs = totalHours % 24L
            val parts = mutableListOf<String>()
            if (days > 0) parts.add("$days ${if (days == 1L) "Day" else "Days"}")
            if (remHrs > 0) parts.add("$remHrs ${if (remHrs == 1L) "Hr" else "Hrs"}")
            if (parts.isEmpty()) return CountdownResult("Less than 1 Hr left", false)
            return CountdownResult("${parts.joinToString(" ")} left", false)
        }

        // < 365 days
        if (days < 365) {
            val months = days / 30L
            val remDays = days % 30L
            val parts = mutableListOf<String>()
            if (months > 0) parts.add("$months ${if (months == 1L) "Month" else "Months"}")
            if (remDays > 0) parts.add("$remDays ${if (remDays == 1L) "Day" else "Days"}")
            return CountdownResult("${parts.joinToString(" ")} left", false)
        }

        // > 1 year
        val years = days / 365L
        val remMonths = (days % 365L) / 30L
        val parts = mutableListOf<String>()
        if (years > 0) parts.add("$years ${if (years == 1L) "Year" else "Years"}")
        if (remMonths > 0) parts.add("$remMonths ${if (remMonths == 1L) "Month" else "Months"}")
        return CountdownResult("${parts.joinToString(" ")} left", false)
    }

    // ── Ticker alarm (refreshes every 60s) ─────────────────────────────
    private fun scheduleTicker(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val triggerAt = System.currentTimeMillis() + 60_000L
        val pendingIntent = tickerPendingIntent(context)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent
            )
        } else {
            alarmManager.set(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
        }
    }

    private fun schedulePreciseUpdate(context: Context, timeMs: Long) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, ExamTrackerWidgetProvider::class.java).apply {
            action = ACTION_WIDGET_TICK
        }
        val pendingIntent = PendingIntent.getBroadcast(
            context, REQUEST_CODE_PRECISE, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP, timeMs, pendingIntent
            )
        } else {
            alarmManager.setExact(AlarmManager.RTC_WAKEUP, timeMs, pendingIntent)
        }
    }

    private fun cancelTicker(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.cancel(tickerPendingIntent(context))
    }

    private fun tickerPendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, ExamTrackerWidgetProvider::class.java).apply {
            action = ACTION_WIDGET_TICK
        }
        return PendingIntent.getBroadcast(
            context, REQUEST_CODE_TICK, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    // ── Helpers ─────────────────────────────────────────────────────────
    private fun getWidgetInt(
        prefs: SharedPreferences, widgetId: Int, key: String, fallback: Int
    ): Int {
        val v = prefs.all["${key}_$widgetId"]
        if (v is Int) return v
        if (v is Long) return v.toInt()
        return fallback
    }

    companion object {
        private const val ACTION_WIDGET_TICK = "com.example.exam_tracker.WIDGET_TICK"
        private const val REQUEST_CODE_TICK = 44221
        private const val REQUEST_CODE_PRECISE = 44222
    }
}
