//
//  SessionRecord.swift
//  Back
//
//  Created by Furkan Öztürk on 9/19/25.
//

import Foundation
import SwiftData

@Model
final class SessionRecord {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var endedAt: Date
    var exerciseCount: Int
    var totalReps: Int
    var autoplayEnabled: Bool

    init(id: UUID = UUID(),
         startedAt: Date,
         endedAt: Date,
         exerciseCount: Int,
         totalReps: Int,
         autoplayEnabled: Bool)
    {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.exerciseCount = exerciseCount
        self.totalReps = totalReps
        self.autoplayEnabled = autoplayEnabled
    }
}

extension SessionRecord {
    var duration: TimeInterval {
        endedAt.timeIntervalSince(startedAt)
    }

    var dayStart: Date {
        Calendar.current.startOfDay(for: startedAt)
    }
}
