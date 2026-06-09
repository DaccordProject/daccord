package com.daccord_projects.daccord

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// Hosts the `com.daccord.app/installer` method channel used by the in-app
/// self-updater (see `lib/features/updates/services/update_installer.dart`).
/// `installApk` opens a downloaded APK with the system package installer via a
/// FileProvider content URI, routing the user to grant "install unknown apps"
/// first when needed.
class MainActivity : FlutterActivity() {
    private val channelName = "com.daccord.app/installer"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrEmpty()) {
                            result.error("no_path", "Missing APK path.", null)
                        } else {
                            try {
                                installApk(path)
                                result.success(null)
                            } catch (e: Exception) {
                                result.error("install_failed", e.message, null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun installApk(path: String) {
        // Android O+ gates sideloading behind a per-app "install unknown apps"
        // permission. Send the user to grant it rather than failing silently.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName"),
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            throw IllegalStateException(
                "Allow installing apps from Daccord, then tap Update again.",
            )
        }

        val file = File(path)
        val uri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            file,
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }
}
