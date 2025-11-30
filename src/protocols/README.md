# Wayland Protocols

This directory will contain Wayland protocol XML files and generated C headers.

## Structure

When protocols are added, they will be organized as:

```
protocols/
├── xdg-shell.xml          # Protocol XML definitions
├── xdg-shell-protocol.h   # Generated C headers (via wayland-scanner)
└── xdg-shell-protocol.c   # Generated C code (via wayland-scanner)
```

## Usage

Protocols will be generated using `wayland-scanner`:

```bash
wayland-scanner server-header < protocol.xml > protocol-protocol.h
wayland-scanner private-code < protocol.xml > protocol-protocol.c
```

## Common Protocols

- **xdg-shell**: Desktop shell protocol for window management
- **wlr-layer-shell**: Layer shell protocol (if needed)
- **wlr-output-management**: Output management (if needed)

---

_This directory is currently empty. Protocols will be added as needed during implementation._

