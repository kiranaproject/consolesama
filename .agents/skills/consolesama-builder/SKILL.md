---
name: consolesama-builder
description: Builds, tests, and verifies consolesama — the Samarinda Desktop terminal emulator built on Floria Toolkit (ftpas) and FTML.
version: 1.0.0
triggers:
  - build consolesama
  - compile consolesama
  - test consolesama
  - test consolesama xephyr
  - run consolesama
  - samarinda terminal
---

# `consolesama` — Samarinda Terminal Emulator Build & Development Skill

Orchestrates the build pipeline, unit tests, and nested Xephyr execution for **consolesama**, the official terminal emulator for the Samarinda Desktop Environment powered by **Floria Toolkit (ftpas)** and **FTML**.

> [!NOTE]
> `consolesama` features a declarative FTML window chrome (`src/main/ftml/consolesama.ftml`) embedded directly into the binary via `tools/ftml_embed.pas`, combined with high-performance native vector canvas terminal rendering (`TFtDrawingArea`), VT100/xterm emulation, and PTY session handling.

---

## 1. Prerequisites & Dependencies

- **Free Pascal Compiler (`fpc` >= 3.2.0)**
- **PasBuild (`pasbuild` >= 1.9.0)**: Reads `project.xml`.
- **Florialib (`florialib:0.0.1-SNAPSHOT`)**: Core vector graphics (AggPas), HarfBuzz, and XCB bindings.
- **Floria Toolkit (`ftpas:0.0.1-SNAPSHOT`)**: Pascal binding (`libft.so`), widget hierarchy, and FTML loader.
- **Xephyr (`/usr/bin/Xephyr`)**: Nested X server for visual verification alongside `wmsama`.

---

## 2. Build & Test Commands

| Action | Command | Description |
| :--- | :--- | :--- |
| **Compile Executable** | `./build.sh` or `pasbuild compile` | Compiles `consolesama` binary to `target/consolesama` |
| **Run Unit Tests** | `./build.sh test` or `pasbuild test` | Compiles and executes test suite `TestRunner` |
| **Clean Artifacts** | `./build.sh clean` or `pasbuild clean` | Cleans `target/` build directory |
| **Regenerate FTML** | `./build.sh ftml` | Compiles `tools/ftml_embed` and regenerates `consolesama.ftml.res.pas` |

---

## 3. Nested Testing with Xephyr (Alongside `wmsama`)

Test `consolesama` inside a nested Xephyr X11 session:

```bash
# 1. Start Xephyr on virtual display :2
Xephyr -br -ac -noreset -screen 1280x720x24 -resizeable :2 &
XEPHYR_PID=$!

# 2. Start wmsama Window Manager
DISPLAY=:2 ../wmsama/target/wmsama &
WM_PID=$!

# 3. Start consolesama Terminal
DISPLAY=:2 ./target/consolesama &
APP_PID=$!

# 4. Clean teardown when finished
kill -9 $APP_PID $WM_PID $XEPHYR_PID 2>/dev/null || true
wait $XEPHYR_PID 2>/dev/null || true
```

---

## 4. `consolesama` Architecture & Components

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    consolesama (Samarinda Terminal)                     │
├─────────────────────────────────────────────────────────────────────────┤
│  Declarative FTML Chrome (consolesama.res / consolesama.ftml)           │
│  - MenuBar: File, Edit, View, Help with keyboard shortcuts              │
│  - Notebook tab host (id: tabHost) for multi-tab sessions               │
│  - StatusBar: shell process PID, terminal dimensions, and status info   │
├─────────────────────────────────────────────────────────────────────────┤
│  Application Window (ConsoleSama.Window)                                │
│  - Inherits TFtFTMLForm to load embedded FTML layout                    │
│  - Manages tabs, keyboard shortcuts (Ctrl+Shift+T/W/C/V/N, Ctrl+Plus/Minus)│
│  - Syncs terminal titles to notebook tab headers                        │
├─────────────────────────────────────────────────────────────────────────┤
│  Terminal View Widget (ConsoleSama.Terminal)                            │
│  - TFtDrawingArea canvas widget rendering text cells via Floria font    │
│  - Translates X11 keysyms to VT sequences (ConsoleSama.Keys)            │
│  - Handles selection, clipboard copy/paste, and font zoom               │
├─────────────────────────────────────────────────────────────────────────┤
│  Terminal Emulator Engine (ConsoleSama.Vt)                              │
│  - ANSI / VT100 / xterm escape sequence parser                          │
│  - 24-bit TrueColor and 256-color palette support                       │
│  - Scrollback buffer, alternate screen buffer, and auto-wrap            │
├─────────────────────────────────────────────────────────────────────────┤
│  PTY Session Handler (ConsoleSama.Pty)                                  │
│  - Posix pseudo-terminal master/slave allocation (openpt, ptsname_r)    │
│  - Forks and executes shell (/bin/bash or $SHELL)                       │
│  - Non-blocking I/O and TIOCSWINSZ window geometry signaling           │
└─────────────────────────────────────────────────────────────────────────┘
```
