# Security Policy

## Reporting a vulnerability

Please report vulnerabilities **privately** through GitHub's private vulnerability reporting:

**[Report a vulnerability](https://github.com/blamechris/DockKeeper/security/advisories/new)** (Security tab ▸ *Report a vulnerability*).

Please do not open a public issue for a security problem. This is a solo-maintained project; you can expect an acknowledgement within a week, best effort. Coordinated disclosure is appreciated — a fix ships in a patch release before the advisory is published.

## Supported versions

DockKeeper is pre-1.0. Only the **latest release** receives security fixes.

| Version | Supported |
|---|---|
| Latest tagged release | ✅ |
| Anything older | ❌ |

## Security posture (what you're auditing)

- **No network code.** The binaries contain no networking symbols, raw socket syscalls, or linked networking frameworks — enforced by a CI gate on every build ([ci.yml](.github/workflows/ci.yml)), and verifiable on your own downloaded copy per [PRIVACY.md](PRIVACY.md). The only outbound action in the product is the user-initiated "Support Development" link.
- **No required permissions.** The single optional permission is Accessibility, used by two opt-in features — *Keep windows in place* (window geometry) and *Keep a bottom Dock on my preferred display* (an event tap over pointer coordinates). [PRIVACY.md](PRIVACY.md) describes exactly what each one reads.
- **One ratified private-API exception.** Dock repositioning uses the private `CoreDock` API under ADR-003 ([docs/decision-log.md](docs/decision-log.md)), resolved at runtime with `dlsym` and degrading to `defaults`/`killall`.

## Known, accepted surface: the `dockkeeper://` URL scheme

The URL scheme is **unauthenticated by design** — any local process that can open a URL can lock, unlock, or pause DockKeeper. This is documented in the [README](README.md#automation) along with the removal instructions (delete `CFBundleURLTypes` from the app's `Info.plist`). The accepted worst case is that the Dock stops being held in place; reports demonstrating that this surface can do **more** than that (read data, change other settings, escalate) are exactly what private reporting is for.
