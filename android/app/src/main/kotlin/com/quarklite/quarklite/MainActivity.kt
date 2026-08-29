package com.quarklite.quarklite

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.provider.Settings
import androidx.annotation.NonNull
import com.gopeed.libgopeed.Libgopeed
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.io.File

open class MainActivity : FlutterActivity() {
    private val GOPEED_CHANNEL = "quarklite.com/gopeed"
    private val SYS_CHANNEL = "quarklite.com/system"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val taskQueue =
            flutterEngine.dartExecutor.binaryMessenger.makeBackgroundTaskQueue()
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            GOPEED_CHANNEL,
            StandardMethodCodec.INSTANCE,
            taskQueue
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val cfg = call.argument<String>("cfg")
                    try {
                        val port = Libgopeed.start(cfg)
                        result.success(port)
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                "stop" -> {
                    Libgopeed.stop()
                    result.success(null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SYS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canWriteDownload" -> result.success(canWriteDownload())
                    "openAllFilesAccess" -> {
                        openAllFilesAccess()
                        result.success(null)
                    }
                    "canIgnoreBattery" -> result.success(canIgnoreBattery())
                    "requestIgnoreBattery" -> {
                        requestIgnoreBattery()
                        result.success(null)
                    }
                    "getSupportedAbis" -> result.success(Build.SUPPORTED_ABIS.toList())
                    else -> result.notImplemented()
                }
            }
    }

    private fun canWriteDownload(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            val dir = File("/storage/emulated/0/Download")
            dir.exists() && dir.canWrite()
        }
    }

    private fun openAllFilesAccess() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                val intent = Intent(
                    android.provider.Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION
                )
                intent.data = Uri.parse("package:$packageName")
                startActivity(intent)
            } catch (e: Exception) {
                startActivity(
                    Intent(android.provider.Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
                )
            }
        } else {
            requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), 0)
        }
    }

    /// 是否已允许忽略电池优化（后台不被系统杀）
    private fun canIgnoreBattery(): Boolean {
        val pm = getSystemService(POWER_SERVICE) as? PowerManager ?: return true
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    /// 引导用户到「忽略电池优化 / 允许后台运行」设置页
    private fun requestIgnoreBattery() {
        try {
            if (canIgnoreBattery()) return
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
            intent.data = Uri.parse("package:$packageName")
            startActivity(intent)
        } catch (e: Exception) {
            // 部分厂商去掉了该入口，回退到应用详情页
            try {
                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                intent.data = Uri.parse("package:$packageName")
                startActivity(intent)
            } catch (_: Exception) {}
        }
    }
}
