package com.aspauldingcode.wawona

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.foundation.clickable
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.net.NetworkInterface

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsDialog(
    prefs: SharedPreferences,
    onDismiss: () -> Unit,
    onApply: () -> Unit
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val context = LocalContext.current
    val localIpAddress = remember { getLocalIpAddress(context) }
    
    ModalBottomSheet(
        onDismissRequest = {
            onApply()
            onDismiss()
        },
        sheetState = sheetState,
        shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp),
        containerColor = MaterialTheme.colorScheme.surface,
        dragHandle = {
            Box(
                modifier = Modifier
                    .padding(vertical = 12.dp)
                    .width(40.dp)
                    .height(4.dp)
                    .background(
                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f),
                        shape = RoundedCornerShape(2.dp)
                    )
            )
        }
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp)
                .padding(bottom = 32.dp)
        ) {
            // Header
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = Icons.Filled.Settings,
                    contentDescription = null,
                    modifier = Modifier.size(28.dp),
                    tint = MaterialTheme.colorScheme.primary
                )
                Spacer(modifier = Modifier.width(12.dp))
                Text(
                    text = "Wawona Settings",
                    style = MaterialTheme.typography.headlineSmall.copy(
                        fontWeight = FontWeight.SemiBold,
                        letterSpacing = (-0.01).sp
                    ),
                    color = MaterialTheme.colorScheme.onSurface
                )
            }
            
            Spacer(modifier = Modifier.height(8.dp))
            HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))
            
            // Display & Rendering Section
            SettingsSectionHeader(
                title = "Display & Rendering",
                icon = Icons.Filled.DesktopWindows
            )
            SettingsSwitchItem(
                prefs = prefs,
                key = "autoScale",
                title = "Auto Scale",
                description = "Detect and match Android UI Scaling",
                icon = Icons.Filled.AspectRatio,
                default = true
            )
            SettingsSwitchItem(
                prefs = prefs,
                key = "respectSafeArea",
                title = "Respect Safe Area",
                description = "Avoid system UI and notches",
                icon = Icons.Filled.Security,
                default = true
            )
            
            Spacer(modifier = Modifier.height(8.dp))
            
            // Advanced Features Section
            SettingsSectionHeader(
                title = "Advanced Features",
                icon = Icons.Filled.Tune
            )
            SettingsSwitchItem(
                prefs = prefs,
                key = "colorOperations",
                title = "Color Operations",
                description = "Enable color profiles, HDR requests, etc.",
                icon = Icons.Filled.Palette,
                default = true
            )
            SettingsSwitchItem(
                prefs = prefs,
                key = "nestedCompositorsSupport",
                title = "Nested Compositors",
                description = "Support nested Wayland compositors",
                icon = Icons.Filled.Layers,
                default = true
            )
            SettingsSwitchItem(
                prefs = prefs,
                key = "multipleClients",
                title = "Multiple Clients",
                description = "Allow multiple Wayland clients",
                icon = Icons.Filled.Group,
                default = false
            )
            
            Spacer(modifier = Modifier.height(8.dp))
            
            // Waypipe Configuration Section
            SettingsSectionHeader(
                title = "Waypipe Configuration",
                icon = Icons.Filled.Wifi
            )
            
            // Local IP Address Display
            Surface(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 4.dp),
                shape = RoundedCornerShape(16.dp),
                color = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.3f)
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        imageVector = Icons.Filled.Info,
                        contentDescription = null,
                        modifier = Modifier.size(24.dp),
                        tint = MaterialTheme.colorScheme.primary
                    )
                    Spacer(modifier = Modifier.width(16.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = "Local IP Address",
                            style = MaterialTheme.typography.bodyLarge.copy(
                                fontWeight = FontWeight.Medium
                            ),
                            color = MaterialTheme.colorScheme.onSurface
                        )
                        Spacer(modifier = Modifier.height(4.dp))
                        Text(
                            text = localIpAddress ?: "Not available",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace
                        )
                    }
                }
            }
            
            // Waypipe Display Socket
            SettingsTextInputItem(
                prefs = prefs,
                key = "waypipeDisplay",
                title = "Wayland Display",
                description = "Display socket name (e.g., wayland-0)",
                icon = Icons.Filled.DesktopWindows,
                default = "wayland-0",
                keyboardType = KeyboardType.Text,
                revertToDefaultOnEmpty = true
            )
            
            // Waypipe Socket Path (read-only on Android/iOS - set by platform)
            val context = LocalContext.current
            val androidSocketPath = remember {
                "${context.cacheDir.absolutePath}/waypipe"
            }
            SettingsTextInputItem(
                prefs = prefs,
                key = "waypipeSocket",
                title = "Socket Path",
                description = "Unix socket path (set by platform)",
                icon = Icons.Filled.Folder,
                default = androidSocketPath,
                keyboardType = KeyboardType.Text,
                readOnly = true
            )
            
            // Compression
            SettingsDropdownItem(
                prefs = prefs,
                key = "waypipeCompress",
                title = "Compression",
                description = "Compression method for data transfers",
                icon = Icons.Filled.Archive,
                default = "lz4",
                options = listOf("none", "lz4", "zstd")
            )
            
            // Compression Level (if zstd selected)
            val compressionMethod = remember { 
                mutableStateOf(prefs.getString("waypipeCompress", "lz4") ?: "lz4")
            }
            LaunchedEffect(prefs.getString("waypipeCompress", "lz4")) {
                compressionMethod.value = prefs.getString("waypipeCompress", "lz4") ?: "lz4"
            }
            
            if (compressionMethod.value == "zstd" || compressionMethod.value.startsWith("zstd=")) {
                SettingsTextInputItem(
                    prefs = prefs,
                    key = "waypipeCompressLevel",
                    title = "Compression Level",
                    description = "Zstd compression level (1-22)",
                    icon = Icons.Filled.Tune,
                    default = "7",
                    keyboardType = KeyboardType.Number
                )
            }
            
            // Threads
            SettingsTextInputItem(
                prefs = prefs,
                key = "waypipeThreads",
                title = "Threads",
                description = "Number of threads (0 = auto)",
                icon = Icons.Filled.Memory,
                default = "0",
                keyboardType = KeyboardType.Number,
                revertToDefaultOnEmpty = true
            )
            
            // Video Compression
            SettingsDropdownItem(
                prefs = prefs,
                key = "waypipeVideo",
                title = "Video Compression",
                description = "DMABUF video compression codec",
                icon = Icons.Filled.VideoCall,
                default = "none",
                options = listOf("none", "h264", "vp9", "av1")
            )
            
            // Video Encoding/Decoding
            val videoCodec = remember { 
                mutableStateOf(prefs.getString("waypipeVideo", "none") ?: "none")
            }
            LaunchedEffect(prefs.getString("waypipeVideo", "none")) {
                videoCodec.value = prefs.getString("waypipeVideo", "none") ?: "none"
            }
            
            if (videoCodec.value != "none") {
                SettingsDropdownItem(
                    prefs = prefs,
                    key = "waypipeVideoEncoding",
                    title = "Video Encoding",
                    description = "Hardware or software encoding",
                    icon = Icons.Filled.Settings,
                    default = "hw",
                    options = listOf("hw", "sw", "hwenc", "swenc")
                )
                SettingsDropdownItem(
                    prefs = prefs,
                    key = "waypipeVideoDecoding",
                    title = "Video Decoding",
                    description = "Hardware or software decoding",
                    icon = Icons.Filled.Settings,
                    default = "hw",
                    options = listOf("hw", "sw", "hwdec", "swdec")
                )
                SettingsTextInputItem(
                    prefs = prefs,
                    key = "waypipeVideoBpf",
                    title = "Bits Per Frame",
                    description = "Target bit rate (e.g., 750000)",
                    icon = Icons.Filled.Speed,
                    default = "",
                    keyboardType = KeyboardType.Number
                )
            }
            
            // SSH Configuration
            SettingsSwitchItem(
                prefs = prefs,
                key = "waypipeSSHEnabled",
                title = "Enable SSH",
                description = "Allow SSH connections for waypipe",
                icon = Icons.Filled.Lock,
                default = false
            )
            
            val sshEnabled = remember { mutableStateOf(prefs.getBoolean("waypipeSSHEnabled", false)) }
            LaunchedEffect(prefs.getBoolean("waypipeSSHEnabled", false)) {
                sshEnabled.value = prefs.getBoolean("waypipeSSHEnabled", false)
            }
            
            if (sshEnabled.value) {
                SettingsTextInputItem(
                    prefs = prefs,
                    key = "waypipeSSHHost",
                    title = "SSH Host",
                    description = "Remote host for SSH connection",
                    icon = Icons.Filled.Computer,
                    default = "",
                    keyboardType = KeyboardType.Text
                )
                SettingsTextInputItem(
                    prefs = prefs,
                    key = "waypipeSSHUser",
                    title = "SSH User",
                    description = "SSH username",
                    icon = Icons.Filled.Person,
                    default = "",
                    keyboardType = KeyboardType.Text
                )
                SettingsTextInputItem(
                    prefs = prefs,
                    key = "waypipeSSHBinary",
                    title = "SSH Binary Path",
                    description = "Path to ssh binary (default: ssh)",
                    icon = Icons.Filled.Build,
                    default = "ssh",
                    keyboardType = KeyboardType.Text
                )
            }
            
            // Advanced Options
            SettingsSwitchItem(
                prefs = prefs,
                key = "waypipeDebug",
                title = "Debug Mode",
                description = "Print debug log messages",
                icon = Icons.Filled.BugReport,
                default = false
            )
            SettingsSwitchItem(
                prefs = prefs,
                key = "waypipeNoGpu",
                title = "Disable GPU",
                description = "Block GPU-accelerated protocols",
                icon = Icons.Filled.Block,
                default = false
            )
            SettingsSwitchItem(
                prefs = prefs,
                key = "waypipeOneshot",
                title = "One Shot",
                description = "Exit after single connection closes",
                icon = Icons.Filled.Stop,
                default = false
            )
            SettingsSwitchItem(
                prefs = prefs,
                key = "waypipeUnlinkSocket",
                title = "Unlink Socket",
                description = "Remove socket file on shutdown",
                icon = Icons.Filled.Delete,
                default = false
            )
            SettingsSwitchItem(
                prefs = prefs,
                key = "waypipeLoginShell",
                title = "Login Shell",
                description = "Open login shell if no command",
                icon = Icons.Filled.Code,
                default = false
            )
            SettingsSwitchItem(
                prefs = prefs,
                key = "waypipeVsock",
                title = "VSock",
                description = "Use vsock for VM communication",
                icon = Icons.Filled.Storage,
                default = false
            )
            SettingsSwitchItem(
                prefs = prefs,
                key = "waypipeXwls",
                title = "XWayland Support",
                description = "Use xwayland-satellite for X clients (unavailable)",
                icon = Icons.Filled.Apps,
                default = false,
                enabled = false
            )
            
            // Title Prefix
            SettingsTextInputItem(
                prefs = prefs,
                key = "waypipeTitlePrefix",
                title = "Title Prefix",
                description = "Prefix for window titles",
                icon = Icons.Filled.TextFields,
                default = "",
                keyboardType = KeyboardType.Text
            )
            
            // Security Context
            SettingsTextInputItem(
                prefs = prefs,
                key = "waypipeSecCtx",
                title = "Security Context",
                description = "Application ID for security context",
                icon = Icons.Filled.Security,
                default = "",
                keyboardType = KeyboardType.Text
            )
            
            Spacer(modifier = Modifier.height(24.dp))
            
            // Apply Button
            Button(
                onClick = {
                    onApply()
                    onDismiss()
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(56.dp),
                shape = RoundedCornerShape(16.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.primaryContainer,
                    contentColor = MaterialTheme.colorScheme.onPrimaryContainer
                )
            ) {
                Text(
                    text = "Apply Settings",
                    style = MaterialTheme.typography.labelLarge.copy(
                        fontWeight = FontWeight.SemiBold
                    )
                )
            }
        }
    }
}

@Composable
fun SettingsSectionHeader(
    title: String,
    icon: ImageVector
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 12.dp, horizontal = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            modifier = Modifier.size(20.dp),
            tint = MaterialTheme.colorScheme.primary
        )
        Spacer(modifier = Modifier.width(8.dp))
        Text(
            text = title,
            style = MaterialTheme.typography.titleMedium.copy(
                fontWeight = FontWeight.SemiBold,
                letterSpacing = (-0.01).sp
            ),
            color = MaterialTheme.colorScheme.primary
        )
    }
}

@Composable
fun SettingsSwitchItem(
    prefs: SharedPreferences,
    key: String,
    title: String,
    description: String,
    icon: ImageVector,
    default: Boolean,
    enabled: Boolean = true
) {
    var checked by remember { mutableStateOf(prefs.getBoolean(key, default)) }
    
    LaunchedEffect(key) {
        if (enabled) {
            checked = prefs.getBoolean(key, default)
        } else {
            // For disabled items, always use default and ensure it's saved
            checked = default
            prefs.edit().putBoolean(key, default).apply()
        }
    }
    
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = if (enabled) 0.4f else 0.2f),
        onClick = {
            if (enabled) {
                checked = !checked
                prefs.edit().putBoolean(key, checked).apply()
            }
        }
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Row(
                modifier = Modifier.weight(1f),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.Start
            ) {
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    modifier = Modifier.size(24.dp),
                    tint = MaterialTheme.colorScheme.primary.copy(alpha = if (enabled) 0.8f else 0.4f)
                )
                Spacer(modifier = Modifier.width(16.dp))
                Column(
                    modifier = Modifier.weight(1f)
                ) {
                    Text(
                        text = title,
                        style = MaterialTheme.typography.bodyLarge.copy(
                            fontWeight = FontWeight.Medium
                        ),
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = if (enabled) 1f else 0.6f)
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = description,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = if (enabled) 1f else 0.6f)
                    )
                }
            }
            Spacer(modifier = Modifier.width(16.dp))
            Switch(
                checked = checked,
                onCheckedChange = {
                    if (enabled) {
                        checked = it
                        prefs.edit().putBoolean(key, it).apply()
                    }
                },
                enabled = enabled,
                colors = SwitchDefaults.colors(
                    checkedThumbColor = MaterialTheme.colorScheme.primary,
                    checkedTrackColor = MaterialTheme.colorScheme.primaryContainer,
                    uncheckedThumbColor = MaterialTheme.colorScheme.onSurfaceVariant,
                    uncheckedTrackColor = MaterialTheme.colorScheme.surfaceVariant,
                    disabledCheckedThumbColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
                    disabledCheckedTrackColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f),
                    disabledUncheckedThumbColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
                    disabledUncheckedTrackColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)
                )
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsTextInputItem(
    prefs: SharedPreferences,
    key: String,
    title: String,
    description: String,
    icon: ImageVector,
    default: String,
    keyboardType: KeyboardType,
    revertToDefaultOnEmpty: Boolean = false,
    readOnly: Boolean = false
) {
    var text by remember { mutableStateOf(prefs.getString(key, default) ?: default) }
    
    LaunchedEffect(key) {
        if (!readOnly) {
            text = prefs.getString(key, default) ?: default
        } else {
            // For read-only fields, always use the default (platform-set value)
            text = default
            // Update preferences to match platform value
            prefs.edit().putString(key, default).apply()
        }
    }
    
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    modifier = Modifier.size(24.dp),
                    tint = MaterialTheme.colorScheme.primary.copy(alpha = 0.8f)
                )
                Spacer(modifier = Modifier.width(16.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = title,
                        style = MaterialTheme.typography.bodyLarge.copy(
                            fontWeight = FontWeight.Medium
                        ),
                        color = MaterialTheme.colorScheme.onSurface
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = description,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            Spacer(modifier = Modifier.height(12.dp))
            OutlinedTextField(
                value = text,
                onValueChange = { newValue ->
                    if (!readOnly) {
                        val finalValue = if (revertToDefaultOnEmpty && newValue.isEmpty()) {
                            default
                        } else {
                            newValue
                        }
                        text = finalValue
                        prefs.edit().putString(key, finalValue).apply()
                    }
                },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                readOnly = readOnly,
                enabled = !readOnly,
                keyboardOptions = KeyboardOptions(keyboardType = keyboardType),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = MaterialTheme.colorScheme.primary,
                    unfocusedBorderColor = MaterialTheme.colorScheme.outline,
                    disabledTextColor = MaterialTheme.colorScheme.onSurfaceVariant,
                    disabledBorderColor = MaterialTheme.colorScheme.outline.copy(alpha = 0.5f)
                ),
                shape = RoundedCornerShape(12.dp)
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsDropdownItem(
    prefs: SharedPreferences,
    key: String,
    title: String,
    description: String,
    icon: ImageVector,
    default: String,
    options: List<String>
) {
    var expanded by remember { mutableStateOf(false) }
    var selectedOption by remember { mutableStateOf(prefs.getString(key, default) ?: default) }
    
    LaunchedEffect(key) {
        selectedOption = prefs.getString(key, default) ?: default
    }
    
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    modifier = Modifier.size(24.dp),
                    tint = MaterialTheme.colorScheme.primary.copy(alpha = 0.8f)
                )
                Spacer(modifier = Modifier.width(16.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = title,
                        style = MaterialTheme.typography.bodyLarge.copy(
                            fontWeight = FontWeight.Medium
                        ),
                        color = MaterialTheme.colorScheme.onSurface
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = description,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            Spacer(modifier = Modifier.height(12.dp))
            Box {
                ExposedDropdownMenuBox(
                    expanded = expanded,
                    onExpandedChange = { expanded = !expanded }
                ) {
                    OutlinedTextField(
                        value = selectedOption,
                        onValueChange = {},
                        readOnly = true,
                        trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
                        modifier = Modifier
                            .fillMaxWidth()
                            .menuAnchor(),
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedBorderColor = MaterialTheme.colorScheme.primary,
                            unfocusedBorderColor = MaterialTheme.colorScheme.outline
                        ),
                        shape = RoundedCornerShape(12.dp)
                    )
                    ExposedDropdownMenu(
                        expanded = expanded,
                        onDismissRequest = { expanded = false }
                    ) {
                        options.forEach { option ->
                            DropdownMenuItem(
                                text = { Text(option) },
                                onClick = {
                                    selectedOption = option
                                    prefs.edit().putString(key, option).apply()
                                    expanded = false
                                }
                            )
                        }
                    }
                }
            }
        }
    }
}

fun getLocalIpAddress(context: Context): String? {
    try {
        val interfaces = NetworkInterface.getNetworkInterfaces()
        while (interfaces.hasMoreElements()) {
            val networkInterface = interfaces.nextElement()
            val addresses = networkInterface.inetAddresses
            while (addresses.hasMoreElements()) {
                val address = addresses.nextElement()
                if (!address.isLoopbackAddress && address.hostAddress != null) {
                    val hostAddress = address.hostAddress
                    if (hostAddress != null && !hostAddress.contains(":")) {
                        return hostAddress
                    }
                }
            }
        }
    } catch (e: Exception) {
        e.printStackTrace()
    }
    return null
}
