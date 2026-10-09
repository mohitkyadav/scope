//
//  TimeFormatting.swift
//  Scope
//

import Foundation

extension TimeInterval {
    /// `0:42`, `12:05`, or `1:02:05` for an hour or more.
    var clockString: String {
        let duration = Duration.seconds(self)
        return self >= 3600
            ? duration.formatted(.time(pattern: .hourMinuteSecond))
            : duration.formatted(.time(pattern: .minuteSecond))
    }

    /// `0:42.3`, with tenths of a second, for the timeline.
    var timecodeString: String {
        let tenths = Int((self * 10).rounded(.down))
        let minutes = tenths / 600
        let seconds = (tenths / 10) % 60
        return String(format: "%d:%02d.%d", minutes, seconds, tenths % 10)
    }
}
