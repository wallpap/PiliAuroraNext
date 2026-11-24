package com.wallpap.piliauroranext

import android.app.Application
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.util.Log

class PiliAuroraApplication : Application() {
    private val iconPreferences by lazy {
        getSharedPreferences("launcher_icon_refresh", MODE_PRIVATE)
    }

    override fun onCreate() {
        super.onCreate()
        refreshLauncherIcon(resources.configuration)
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        refreshLauncherIcon(newConfig)
    }

    private fun refreshLauncherIcon(configuration: Configuration) {
        val nightMode = configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
        if (nightMode != Configuration.UI_MODE_NIGHT_NO &&
            nightMode != Configuration.UI_MODE_NIGHT_YES
        ) return
        try {
            if (iconPreferences.getInt("night_mode", Configuration.UI_MODE_NIGHT_UNDEFINED) == nightMode) {
                return
            }
            val marker = ComponentName(this, LauncherIconRefreshMarker::class.java)
            val nextState = when (packageManager.getComponentEnabledSetting(marker)) {
                PackageManager.COMPONENT_ENABLED_STATE_DEFAULT ->
                    PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                else -> PackageManager.COMPONENT_ENABLED_STATE_DEFAULT
            }
            packageManager.setComponentEnabledSetting(marker, nextState, PackageManager.DONT_KILL_APP)
            iconPreferences.edit().putInt("night_mode", nightMode).apply()
        } catch (error: RuntimeException) {
            Log.w("LauncherIconRefresh", "Could not notify the launcher of the system theme change", error)
        }
    }
}

class LauncherIconRefreshMarker : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) = Unit
}
