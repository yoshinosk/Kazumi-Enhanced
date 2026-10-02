package com.example.kazumi

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

// 开机自启：系统开机广播触发时检查开关并拉起应用。
// 开关状态由 MainActivity 的 auto_start channel 写入原生 SharedPreferences
// （receiver 运行时 Flutter 引擎尚未启动，无法读取 Hive）。
class BootCompletedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        val prefs = context.getSharedPreferences(
            MainActivity.AUTO_START_PREFS_NAME, Context.MODE_PRIVATE
        )
        if (!prefs.getBoolean(MainActivity.AUTO_START_PREF_KEY, false)) return
        try {
            context.startActivity(
                Intent(context, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
            )
        } catch (ignored: Exception) {
            // 部分系统限制后台拉起 Activity，静默失败即可。
        }
    }
}
