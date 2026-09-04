import Foundation

/// The three duration formats this package renders elapsed time in. Was
/// `TimeEntriesViewModel.formattedDuration` and
/// `WorkHoursContent.formattedDuration` — two near-identical formatters on
/// two screens that issue #89 merged into one, so they collapse here rather
/// than following either deleted screen into the grave.
///
/// A pure `enum` namespace with no state, so all three formats stay unit-testable
/// at this package's pure-logic seam (`PCCDurationTests`) without a view.
public enum PCCDuration {
    /// "1H 32M" past an hour, "37M" until then — the upper-case
    /// duration-*stamp* treatment, for a figure set beside a
    /// `pccPanelLabel()` in a status strip or on a glass row's readout.
    /// Truncates sub-minute remainders rather than rounding, and clamps a
    /// negative interval to `0M`.
    public static func stamp(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours)H \(String(format: "%02d", minutes))M"
        }
        return "\(minutes)M"
    }

    /// "1h 30m" / "45m" — the quieter lower-case treatment, for a total
    /// sitting inside running text or in a dense tree row where the
    /// stamp's upper-case weight would shout.
    public static func compact(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int(seconds)) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    /// "1:02:03" / "02:03" — the ticking readout a *running* timer shows,
    /// at second resolution rather than the whole minutes the two settled
    /// formats above round to, since a live timer is meant to visibly move.
    /// Kept here beside them rather than as a view-local helper (which is
    /// how both the deleted `TimeEntriesView` and `OverviewView` each had
    /// their own copy) so all three formats are testable at one seam.
    public static func elapsed(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }
}
