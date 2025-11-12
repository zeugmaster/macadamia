//
//  NostrService.swift
//  macadamia
//
//  Created by zm on 09.11.25.
//

import SwiftUI
import NostrSDK
import Observation
import SwiftData

@Observable
class NostrService {
    
    private var container: ModelContainer
    
    init() {
        let schema = Schema([
            //... add models
        ])
        container = try! ModelContainer(for: schema)
    }
    
    
    func start() {
        
    }
    
    func stop() {
        
    }
    
}
