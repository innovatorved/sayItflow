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
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import com.sayitflow.android.ui.DashboardScreen

class MainActivity : ComponentActivity() {

    private var hasMicPermission by mutableStateOf(false)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        @Suppress("DEPRECATION")
        window.statusBarColor = android.graphics.Color.parseColor("#FBF3E4")
        @Suppress("DEPRECATION")
        window.navigationBarColor = android.graphics.Color.parseColor("#FBF3E4")
        WindowCompat.getInsetsController(window, window.decorView)?.apply {
            isAppearanceLightStatusBars = true
            isAppearanceLightNavigationBars = true
        }

        val coordinator = SayItFlowCoordinator.getInstance(this)
        refreshPermissions(coordinator)

        setContent {
            val micLauncher = rememberLauncherForActivityResult(
                contract = ActivityResultContracts.RequestPermission()
            ) { granted ->
                hasMicPermission = granted
            }

            MaterialTheme(
                colorScheme = lightColorScheme(
                    primary = Color(0xFFFF3B2F),
                    onPrimary = Color(0xFFFFFFFF),
                    secondary = Color(0xFF36C2AD),
                    background = Color(0xFFFBF3E4),
                    surface = Color(0xFFFFFFFF),
                    onBackground = Color(0xFF1B1712),
                    onSurface = Color(0xFF1B1712)
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
        if (coordinator.vozEngine.areModelFilesInstalled()) {
            coordinator.vozEngine.warmUpAsync()
        }
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
