//
//  AlertModel.swift
//  Guardify
//
//  Created by Swopnil Panday on 10/19/24.
//

import Foundation
import SwiftData

@Model
final class AlertModel {
    var timestamp: Date
    var message: String

    init(timestamp: Date, message: String) {
        self.timestamp = timestamp
        self.message = message
    }
}
