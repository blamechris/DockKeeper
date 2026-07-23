# DockKeeper Privacy Statement

DockKeeper is built on a simple rule: **nothing ever leaves your Mac.**

- **No telemetry, no analytics.** DockKeeper collects no usage data, no
  crash reports, no identifiers — nothing, on or off the device.
- **No network communication.** The app contains no networking code and makes
  zero network requests during operation. The only outbound action of any kind
  is the "Support Development" menu item, which opens the project's GitHub
  page in your browser when *you* click it.
- **No accounts, no ads, no payment gates.** There is nothing to sign in to
  and nothing to buy.
- **Local logs only, opt-in, bounded.** By default DockKeeper writes nothing
  to disk beyond your preferences. If you enable verbose logging, extra detail
  goes to the macOS unified log (visible in Console.app, system-managed
  retention). If you enable the diagnostics file (Preferences ▸ Advanced), a
  small local log of state changes and Dock corrections is kept — capped
  around 1 MB and pruned after 7 days — so *you* can choose to attach it to a
  bug report. Log lines contain Dock edges, event names, and display state;
  never window titles, application names, documents, or anything else
  sensitive.
- **Preferences stay in your user account.** Settings live in standard macOS
  user defaults on your Mac; the identity of your preferred display is stored
  as hardware identifiers (UUID, vendor/model/serial, display name) for
  matching only.
- **No special permissions.** DockKeeper requests no Accessibility, screen
  recording, or other privacy-gated permission. Launch at Login uses the
  standard macOS Login Items mechanism, which you approve in System Settings.

This statement describes the app as built; the "no network" property is
verifiable from the source (no networking APIs are referenced anywhere) and is
enforced as a release gate. If any future feature ever needed a network
request (for example, an optional update check), it would be off by default,
clearly disclosed, and this statement would be updated first.
