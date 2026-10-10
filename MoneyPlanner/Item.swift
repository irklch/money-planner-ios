//
//  Item.swift
//  MoneyPlanner
//
//  Created by Ирина Кольчугина on 11.10.2026.
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
