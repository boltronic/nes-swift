//
//  nesApp.swift
//  nes
//
//  Created by mike on 7/27/25.
//

import SwiftUI
import Foundation

@main
struct nesApp: App {
    init() {
        #if DEBUG
        print("=== Running Tests (Debug Mode) ===")
        runAllTests()
        print("=== Tests Complete ===\n")
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
