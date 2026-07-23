---
name: Bug report
about: Something went wrong (Dock not restored, wrong display, oscillation, …)
labels: bug
---

**What happened?**
A clear description of the problem.

**What did you expect?**

**Steps to reproduce**
1.
2.

**Setup**
- macOS version:
- DockKeeper version (menu ▸ Preferences, or `dockkeeper status`):
- Displays (count, models, portrait/landscape, how connected — direct/dock/adapter):
- "Displays have separate Spaces" (System Settings ▸ Desktop & Dock): on / off
- Install method: release download / Homebrew / built from source

**Diagnostics**
Please paste the output of:

```
DockKeeper --diagnostics
```

If the issue involves recovery (Dock not coming back after sleep/unplug),
enable **Preferences ▸ Advanced ▸ Write a diagnostics file**, reproduce the
issue, then attach the file from **Reveal Diagnostics File**. It contains only
state names and Dock edges — no personal data (see PRIVACY.md).
