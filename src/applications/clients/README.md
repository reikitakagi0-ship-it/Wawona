# Ported Wayland Client Applications

This directory contains Linux Wayland client applications ported to macOS/iOS.

## Clients

### Firefox
- **Status**: Planned
- **Purpose**: Web browser with Wayland support
- **Porting**: In progress

### KDE Applications
- **Status**: Planned
- **Purpose**: KDE application suite
- **Applications**: Dolphin, Kate, Konsole, etc.
- **Porting**: In progress

### GNOME Applications
- **Status**: Planned
- **Purpose**: GNOME application suite
- **Applications**: Nautilus, Gedit, Terminal, etc.
- **Porting**: In progress

### Ghostty
- **Status**: Planned
- **Purpose**: Terminal emulator
- **Porting**: In progress

### libweston Tests
- **Status**: Available
- **Purpose**: Test clients for Wayland features
- **Tests**: simple-shm, simple-egl, etc.
- **Location**: `dependencies/weston/`

## Porting Process

1. Clone upstream repository
2. Add compatibility layers
3. Update build system for iOS/macOS
4. Test with Wawona compositor
5. Document porting process

## Build System

Each client should:
- Build with strict compilation flags
- Support iOS and macOS
- Connect to Wawona compositor
- Use Wayland protocols properly

## Testing

Test each client:
```bash
# Launch Wawona
./Wawona &

# Launch client
WAYLAND_DISPLAY=wayland-0 firefox --platform=wayland
```

