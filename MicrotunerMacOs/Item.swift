//
//  Item.swift
//  MicrotunerMacOs
//
//  Created by Ghifar on 20.08.25.
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
