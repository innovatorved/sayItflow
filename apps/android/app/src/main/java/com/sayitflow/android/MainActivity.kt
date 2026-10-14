package com.sayitflow.android

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.core.content.ContextCompat
import com.sayitflow.android.ui.DashboardScreen

class MainActivity : ComponentActivity() {

    private var hasMicPermission by mutableStateOf(false)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val coordinator = SayItFlowCoordinator.getInstance(this)
        refreshPermissions(coordinator)

        setContent {
            val micLauncher = rememberLauncherForActivityResult(
                contract = ActivityResultContracts.RequestPermission()
            ) { granted ->
                hasMicPermission = granted
            }

            MaterialTheme(
                colorScheme = darkColorScheme(
                    primary = Color(0xFFFAFAFA),
                    background = Color(0xFF09090B),
                    surface = Color(0xFF121215)
                )
            ) {
                DashboardScreen(
                    coordinator = coordinator,
                    hasMicPermission = hasMicPermission,
                    onRequestMicPermission = {
                        micLauncher.launch(Manifest.permission.RECORD_AUDIO)
                    },
                    onOpenAccessibilitySettings = {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                    }
                )
            }
        }
    }

    override fun onResume() {
        super.onResume()
        val coordinator = SayItFlowCoordinator.getInstance(this)
        refreshPermissions(coordinator)
        coordinator.downloadManager.refreshStatus()
    }

    private fun refreshPermissions(coordinator: SayItFlowCoordinator) {
        hasMicPermission = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED

        val enabledServices = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ).orEmpty()
        val isServiceEnabled = enabledServices.contains(packageName, ignoreCase = true)
        coordinator.setAccessibilityConnected(isServiceEnabled)
    }
}
