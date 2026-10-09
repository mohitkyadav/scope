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
}
