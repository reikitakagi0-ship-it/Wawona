# Ported Linux Applications

This directory contains Linux Wayland applications that have been ported to macOS/iOS.

## Structure

```
applications/
├── compositors/         # Ported Wayland compositors
│   ├── kde-plasma/     # KDE Plasma desktop
│   ├── gnome/          # GNOME desktop
│   ├── sway/           # Sway compositor
│   ├── hyprland/       # Hyprland compositor
│   ├── xfce4/          # XFCE4 desktop
│   └── niri/           # Niri compositor
└── clients/            # Ported Wayland client applications
    ├── firefox/        # Firefox browser
    ├── kde-apps/       # KDE applications
    ├── gnome-apps/     # GNOME applications
    └── ghostty/        # Ghostty terminal
```

## Porting Strategy

Each ported application:
1. **Uses compatibility layers** from `compat/ios/` and `compat/macos/`
2. **Uses stubs** from `stubs/` where needed
3. **Native implementations** where possible
4. **Strict compilation** with `-Werror`
5. **Type-safe code** throughout

## Build System

Each application has its own build system:
- Meson (preferred)
- CMake
- Autotools

All builds must:
- Use strict compilation flags
- Link statically where possible
- Support iOS and macOS
- Be App Store compliant

## Testing

Each application should:
- Build successfully on macOS
- Build successfully on iOS
- Run as nested compositor/client
- Pass all tests
- Work with Wawona compositor

## Status

### Compositors
- [ ] KDE Plasma - In progress
- [ ] GNOME - Planned
- [ ] Sway - Planned
- [ ] Hyprland - Planned
- [ ] XFCE4 - Planned
- [ ] Niri - Planned

### Clients
- [ ] Firefox - Planned
- [ ] KDE Apps - Planned
- [ ] GNOME Apps - Planned
- [ ] Ghostty - Planned

## Contributing

When porting an application:
1. Create directory in appropriate subfolder
2. Clone upstream repository
3. Add compatibility layers
4. Update build system
5. Test thoroughly
6. Document porting process
7. Create patches for modifications

