import Foundation

public extension Date {
    /// Creates a `Date` from a Unix timestamp that may be in seconds or milliseconds.
    ///
    /// Codex RPC and API responses can return timestamps in either second (10 digits
    /// for dates after 2001-09-09) or millisecond (13 digits) resolution. This
    /// initializer detects the resolution and normalizes to seconds before creating
    /// the `Date`.
    ///
    /// - Parameter timestamp: A numeric timestamp as `TimeInterval` (Double).
    init(timestamp: TimeInterval) {
        if timestamp > 1_000_000_000_000 {
            // Millisecond resolution (13+ digits): values > Sep 2001 in ms.
            self.init(timeIntervalSince1970: timestamp / 1000)
        } else {
            self.init(timeIntervalSince1970: timestamp)
        }
    }
}