//
//  Item.swift
//  WoodCut
//
//  Created by Tanush Shrivastava on 3/14/26.
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
