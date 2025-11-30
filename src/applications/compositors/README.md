# Ported Wayland Compositors

This directory contains Linux Wayland compositors ported to macOS/iOS.

## Compositors

### Weston
- **Status**: Testing compositor (not dependency)
- **Purpose**: Test nested compositor support
- **Location**: `dependencies/weston/`
- **Usage**: Launch from Wawona App Launcher

### KDE Plasma
- **Status**: Planned
- **Purpose**: Full KDE desktop environment
- **Porting**: In progress

### GNOME
- **Status**: Planned
- **Purpose**: GNOME desktop environment
- **Porting**: In progress

### Sway
- **Status**: Planned
- **Purpose**: i3-compatible Wayland compositor
- **Porting**: In progress

### Hyprland
- **Status**: Planned
- **Purpose**: Dynamic tiling compositor
- **Porting**: In progress

### XFCE4
- **Status**: Planned
- **Purpose**: Lightweight desktop environment
- **Porting**: In progress

### Niri
- **Status**: Planned
- **Purpose**: Scrollable tiling compositor
- **Porting**: In progress

## Porting Process

1. Clone upstream repository
2. Add compatibility layers (`compat/ios/`, `compat/macos/`)
3. Add stubs where needed (`stubs/`)
4. Update build system
5. Test nested compositor functionality
6. Document porting process

## Build System

Each compositor should:
- Build with strict compilation flags
- Support iOS and macOS
- Work as nested compositor in Wawona
- Use Wawona's Wayland socket

## Testing

Test each compositor:
```bash
# Launch Wawona
./Wawona &

# Launch nested compositor
weston --backend=wayland --no-config
```

