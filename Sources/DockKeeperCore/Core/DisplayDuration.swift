import Foundation

/// Whole-second rendering for the `--diagnostics` report.
///
/// Exists because `Int(_: Double)` **traps** — on NaN, on infinity, and on
/// anything outside `Int`'s range — and every interval the report prints is
/// derived from a `Date` decoded out of `UserDefaults`, a store any process
/// running as this user can write. A support command that crashes on a
/// malformed record is strictly worse than one that prints "unreadable": the
/// entire point of `--diagnostics` is that the user can run it and paste the
/// output, and an `LSUIElement` app gives support nowhere else to look.
public enum DisplayDuration {

    /// The widest magnitude that survives `Int(_: Double)`.
    ///
    /// Deliberately **not** `Double(Int.max)`. That constant rounds *up* past
    /// `Int.max`, so using it as the clamp bound would trap on exactly the
    /// conversion it was introduced to make safe — the compiler constant-folds
    /// `Int(Double(Int.max))` into an overflow error, which is the same defect
    /// caught at build time rather than in a user's support report. `9.0e18` is
    /// comfortably under `Int.max` and exactly representable as a `Double`.
    private static let bound: TimeInterval = 9.0e18

    /// `interval` as whole seconds, or `nil` when it is not a sane quantity.
    ///
    /// Measured: `{"pausedAt": 1e300}` is valid JSON, decodes cleanly to a
    /// `Date`, and crashes the conversion with *"Double value cannot be
    /// converted to Int because the result would be less than Int.min"*. Note
    /// what that rules out — the decoded value is **finite**, so an `isFinite`
    /// guard alone does not fix it. The range check is the load-bearing half;
    /// `isFinite` is kept only because it states the NaN case out loud.
    public static func wholeSeconds(_ interval: TimeInterval) -> Int? {
        guard interval.isFinite, abs(interval) <= bound else { return nil }
        return Int(interval)
    }
}
