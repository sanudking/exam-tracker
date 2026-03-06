package com.example.exam_tracker

import android.app.AlarmManager
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  private val deviceChannel = "exam_tracker/device"

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, deviceChannel)
        .setMethodCallHandler { call, result ->
          when (call.method) {
            "openExactAlarmSettings" -> result.success(openExactAlarmSettings())
            "openBatteryOptimizationSettings" ->
                result.success(openBatteryOptimizationSettings())
            "openNotificationSettings" -> result.success(openNotificationSettings())
            "openAutoStartSettings" -> result.success(openAutoStartSettings())
            "canScheduleExactAlarms" -> result.success(canScheduleExactAlarms())
            "isIgnoringBatteryOptimizations" ->
                result.success(isIgnoringBatteryOptimizations())
            "areNotificationsEnabled" -> result.success(areNotificationsEnabled())
            else -> result.notImplemented()
          }
        }
  }

  private fun openExactAlarmSettings(): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return false
    val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
      data = Uri.parse("package:$packageName")
      addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
    return safeStart(intent)
  }

  private fun openBatteryOptimizationSettings(): Boolean {
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
      val requestIntent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
        data = Uri.parse("package:$packageName")
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      }
      if (safeStart(requestIntent)) {
        true
      } else {
        val fallback = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
          addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        safeStart(fallback)
      }
    } else {
      false
    }
  }

  private fun openNotificationSettings(): Boolean {
    val intent =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
          Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
            putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
          }
        } else {
          Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.fromParts("package", packageName, null)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
          }
        }
    return safeStart(intent)
  }

  private fun openAutoStartSettings(): Boolean {
    val intents =
        listOf(
            // Xiaomi
            Intent().apply {
              component =
                  ComponentName(
                      "com.miui.securitycenter",
                      "com.miui.permcenter.autostart.AutoStartManagementActivity",
                  )
            },
            // Oppo
            Intent().apply {
              component =
                  ComponentName(
                      "com.coloros.safecenter",
                      "com.coloros.safecenter.permission.startup.StartupAppListActivity",
                  )
            },
            // Vivo
            Intent().apply {
              component =
                  ComponentName(
                      "com.vivo.permissionmanager",
                      "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
                  )
            },
            // Huawei
            Intent().apply {
              component =
                  ComponentName(
                      "com.huawei.systemmanager",
                      "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
                  )
            },
            // Samsung
            Intent().apply {
              component =
                  ComponentName(
                      "com.samsung.android.lool",
                      "com.samsung.android.sm.ui.battery.BatteryActivity",
                  )
            },
        )

    for (intent in intents) {
      intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      if (safeStart(intent)) return true
    }

    val appDetails = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
      data = Uri.fromParts("package", packageName, null)
      addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
    return safeStart(appDetails)
  }

  private fun canScheduleExactAlarms(): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
    val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
    return alarmManager.canScheduleExactAlarms()
  }

  private fun isIgnoringBatteryOptimizations(): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
    val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
    return powerManager.isIgnoringBatteryOptimizations(packageName)
  }

  private fun areNotificationsEnabled(): Boolean {
    return NotificationManagerCompat.from(this).areNotificationsEnabled()
  }

  private fun safeStart(intent: Intent): Boolean {
    return try {
      startActivity(intent)
      true
    } catch (_: ActivityNotFoundException) {
      false
    } catch (_: Exception) {
      false
    }
  }
}
