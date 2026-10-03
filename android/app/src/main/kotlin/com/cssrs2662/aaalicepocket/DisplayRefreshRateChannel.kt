package com.cssrs2662.aaalicepocket

import android.app.Activity
import android.os.Build
import android.view.Display
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Asks the system for the panel's fastest refresh mode at the current
 * resolution. Without a request some OEM builds (ColorOS) keep apps at 60 Hz
 * when idle and 90 Hz while touched, even on 120 Hz panels.
 */
class DisplayRefreshRateChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    private val channel = MethodChannel(messenger, CHANNEL).apply {
        setMethodCallHandler { call, result ->
            when (call.method) {
                "setHighRefreshRate" -> {
                    apply(call.argument<Boolean>("enabled") ?: true)
                    result.success(currentRefreshRate())
                }
                else -> result.notImplemented()
            }
        }
    }

    fun apply(enabled: Boolean) {
        val window = activity.window ?: return
        val params = window.attributes
        if (enabled) {
            val best = fastestModeAtCurrentResolution() ?: return
            params.preferredDisplayModeId = best.modeId
        } else {
            params.preferredDisplayModeId = 0
        }
        window.attributes = params
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    private fun display(): Display? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activity.display
        } else {
            @Suppress("DEPRECATION")
            activity.windowManager.defaultDisplay
        }

    private fun fastestModeAtCurrentResolution(): Display.Mode? {
        val display = display() ?: return null
        val current = display.mode
        return display.supportedModes
            .filter {
                it.physicalWidth == current.physicalWidth &&
                    it.physicalHeight == current.physicalHeight
            }
            .maxByOrNull { it.refreshRate }
    }

    private fun currentRefreshRate(): Double =
        display()?.refreshRate?.toDouble() ?: 0.0

    private companion object {
        const val CHANNEL = "com.aaalice.nai_launcher/display"
    }
}
