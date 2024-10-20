//
//  Alert.swift
//  Guardify
//
//  Created by Swopnil Panday on 10/19/24.
//

import Foundation
import SwiftData

@Model
final class Alert {
    var timestamp: Date
    var isEmergency: Bool
    var audioRecordingURL: URL?
    var location: String?  // We'll use a string for now, but consider using CLLocation in the future
    
    init(timestamp: Date, isEmergency: Bool, audioRecordingURL: URL? = nil, location: String? = nil) {
        self.timestamp = timestamp
        self.isEmergency = isEmergency
        self.audioRecordingURL = audioRecordingURL
        self.location = location
    }
}
