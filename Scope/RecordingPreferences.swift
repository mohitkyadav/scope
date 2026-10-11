//
//  RecordingPreferences.swift
//  Scope
//

import Foundation

/// Recording options from the Settings window.
enum RecordingPreferences {
    static let countdownKey = "recordingCountdown"
    static let frameRateKey = "recordingFrameRate"

    /// Seconds of countdown before recording starts; 0 starts straight away.
    static var countdown: Int {
        UserDefaults.standard.object(forKey: countdownKey) as? Int ?? 3
    }

    /// Frames per second to record: 60 or 30.
    static var frameRate: Int {
        UserDefaults.standard.integer(forKey: frameRateKey) == 30 ? 30 : 60
    }
}
