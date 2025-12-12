package com.aspauldingcode.wawona

import android.content.SharedPreferences

object WawonaSettings {
    fun apply(prefs: SharedPreferences) {
        // Map new settings keys to native function parameters
        // For Android: Force SSR is always enabled (always true)
        val forceServerSideDecorations = true
        
        // Auto Scale (Android) maps to autoRetinaScaling for native compatibility
        // Support both old and new keys for backward compatibility
        val autoScale = prefs.getBoolean("autoScale", true) || 
                       prefs.getBoolean("autoRetinaScaling", true)
        
        val renderingBackend = prefs.getInt("renderingBackend", 0)
        val respectSafeArea = prefs.getBoolean("respectSafeArea", true)
        
        // Render macOS Pointer - not applicable on Android, always false
        val renderMacOSPointer = false
        
        // Swap CMD - not applicable on Android, always false
        val swapCmdAsCtrl = false
        
        val universalClipboard = prefs.getBoolean("universalClipboard", true)
        
        // Color Operations (renamed from ColorSync Support)
        val colorOperations = prefs.getBoolean("colorOperations", true) ||
                             prefs.getBoolean("colorSyncSupport", false)
        
        val nestedCompositorsSupport = prefs.getBoolean("nestedCompositorsSupport", true)
        
        // Use Metal 4 - removed, always false
        val useMetal4ForNested = false
        
        // Multiple Clients - disabled by default on Android
        val multipleClients = prefs.getBoolean("multipleClients", false)
        
        // Waypipe RS Support - always enabled, always true
        val waypipeRSSupport = true
        
        // TCP Listener - removed, always false
        val enableTCPListener = false
        
        // TCP Port - no longer used but kept for compatibility
        val tcpPort = try { 
            prefs.getString("tcpPort", "1234")?.toInt() ?: 1234 
        } catch (e: Exception) { 
            1234 
        }
        
        WawonaNative.nativeApplySettings(
            forceServerSideDecorations,
            autoScale,
            renderingBackend,
            respectSafeArea,
            renderMacOSPointer,
            swapCmdAsCtrl,
            universalClipboard,
            colorOperations,
            nestedCompositorsSupport,
            useMetal4ForNested,
            multipleClients,
            waypipeRSSupport,
            enableTCPListener,
            tcpPort
        )
    }
}
