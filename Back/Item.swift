//
//  Item.swift
//  Back
//
//  Created by Furkan Öztürk on 9/19/25.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
