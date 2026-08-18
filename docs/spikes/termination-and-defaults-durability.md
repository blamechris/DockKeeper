# Spike — termination hooks and `UserDefaults` durability

**Date.** 2026-08-17 · **Rig.** macOS 26 (Darwin 25.6), Apple silicon · **For.** ADR-013 / DK-FR-013 (issue #29)

Three claims in ADR-013 rest on measurement rather than on documentation. This note carries
the probe sources and the exact commands so they can be re-run, per kickoff rule 6 — the
same reason `coredock-defaults-persistence.md` exists. Everything here is a standalone
probe; none of it is DockKeeper code, and nothing here touched the real Dock.

## Probe 1 — does a `UserDefaults` write survive an immediate `SIGKILL`?

This is the load-bearing one: the write-ahead ordering in `ScreenShareHider.evaluate` is
worthless if the record can be lost to the very death it exists to survive. Deliberately
written in the production shape — a **named suite**, a **JSON blob**, and **no
`synchronize()`** — and read back from a **fresh process**, so a value that only ever lived
in the dying process's cache would read as absent.

```swift
// durability.swift — swiftc -O durability.swift -o durprobe
import Foundation
struct Record: Codable { let hiddenAt: Date }
let suite = "com.dockkeeper.spike.durability"
let defaults = UserDefaults(suiteName: suite)!
switch CommandLine.arguments.dropFirst().first ?? "" {
case "write":
    let data = try! JSONEncoder().encode(Record(hiddenAt: Date()))
    defaults.set(data, forKey: "screenShareHideRecord")   // no synchronize()
    kill(getpid(), SIGKILL)                                // die immediately
case "read":
    print(defaults.data(forKey: "screenShareHideRecord") == nil ? "ABSENT" : "PRESENT")
case "wipe":
    defaults.removeObject(forKey: "screenShareHideRecord")
default: print("usage: durprobe write|read|wipe")
}
```

```bash
present=0; absent=0
for i in $(seq 1 25); do
  ./durprobe wipe
  ./durprobe write 2>/dev/null      # killed by its own SIGKILL
  [ "$(./durprobe read)" = "PRESENT" ] && present=$((present+1)) || absent=$((absent+1))
done
echo "PRESENT=$present ABSENT=$absent"
```

**Result: `PRESENT=25 ABSENT=0`.** `set` hands the value to `cfprefsd` — a *surviving*
process — over XPC before it returns, so no `synchronize()` is needed and none is used on
the hide path.

**Scope, stated narrowly.** This establishes durability against **process** death only:
`SIGKILL`, Force Quit, a crash, the logout kill. It says nothing about kernel panic or
power loss, which stay **UNKNOWN** in ADR-013. An attempt to bound that by watching for
`~/Library/Preferences/<suite>.plist` to appear on disk was **inconclusive** on this rig
(the file was present immediately, but the probe cannot distinguish a genuine flush from
`cfprefsd` re-materialising the file from its own cache after the `rm`), so no flush-latency
number is claimed here. The residual failure mode is exactly today's behavior — no
regression — and the manual recovery (DK-FR-013 S11) is its answer.

## Probes 2 and 3 — `SIGTERM` disposition, and the `NSApp.terminate` path

One probe answers both, with the signal sources switched by an environment variable so the
two runs differ only in the thing being measured. It is the real shape: an `NSApplication`
with a delegate, `.accessory` activation policy (DockKeeper is `LSUIElement`), and the same
`SIG_IGN` + `DispatchSourceSignal(queue: .main)` construction as `TerminationSignals`.

```swift
// termprobe.swift — swiftc -O termprobe.swift -o termprobe
import AppKit
import Dispatch

final class Delegate: NSObject, NSApplicationDelegate {
    var sources: [DispatchSourceSignal] = []
    let installSources = ProcessInfo.processInfo.environment["INSTALL_SOURCES"] == "1"

    func applicationWillFinishLaunching(_ note: Notification) {
        guard installSources else { return }
        for sig in [SIGTERM, SIGINT] as [Int32] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                print("SIGNAL \(sig)"); fflush(stdout)
                NSApp.terminate(nil)
            }
            source.resume()
            sources.append(source)
        }
    }
    func applicationDidFinishLaunching(_ note: Notification) {
        print("DID_FINISH pid=\(getpid()) sources=\(installSources)"); fflush(stdout)
    }
    func applicationWillTerminate(_ note: Notification) {
        print("WILL_TERMINATE"); fflush(stdout)
    }
}

let app = NSApplication.shared
let delegate = Delegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

```bash
INSTALL_SOURCES=0 ./termprobe > outA.txt 2>&1 & pid=$!; sleep 2; kill -TERM $pid; wait $pid; echo "exit=$?"; cat outA.txt
INSTALL_SOURCES=1 ./termprobe > outB.txt 2>&1 & pid=$!; sleep 2; kill -TERM $pid; wait $pid; echo "exit=$?"; cat outB.txt
```

**Run A — bare AppKit, no sources:**

```
exit=143
DID_FINISH pid=38627 sources=false
```

`applicationWillTerminate` never ran. AppKit installs no `SIGTERM` handler, so the default
terminate-now disposition applies and the delegate is skipped entirely. Exit 143 is
`128 + SIGTERM`.

**Run B — with the dispatch sources installed:**

```
exit=0
DID_FINISH pid=38631 sources=true
SIGNAL 15
WILL_TERMINATE
```

The signal is converted to the ordinary AppKit quit: the handler runs on the main queue,
`NSApp.terminate(nil)` posts `willTerminateNotification`, the delegate runs, and the process
exits 0. This is both claims at once — that the sources are *necessary*, and that
`NSApp.terminate(nil)` reaches `applicationWillTerminate` (the ⌘Q path).

## What these probes do **not** establish

- **The logout / restart / shutdown path.** loginwindow *sends* the Quit Apple Event to a
  background process but does not wait for the reply before killing it (Apple, *System
  Startup Programming Topics*, "Terminating Processes"). That is documentation, not a
  measurement, and it is why ADR-013 treats the termination hook as a latency optimization
  and the persisted record as the mechanism.
- **The real signed bundle.** These probes are unbundled binaries with the same lifecycle
  shape, not DockKeeper itself. The on-device cells stay open — see
  [test-strategy.md](../test-strategy.md) §3c and
  [hardware-matrix-results.md](../hardware-matrix-results.md).
- **Anything about `CGSIsScreenWatcherPresent` or the real Dock.** Untouched here.
