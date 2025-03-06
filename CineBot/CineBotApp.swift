//
//  CineBotApp.swift
//  CineBot
//
//  Created by Alan Digital on 28/02/2025.
//

import SwiftUI

@main
struct CineBotApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(HiddenTitleBarWindowStyle()) // Optionnel
        .defaultSize(width: NSScreen.main?.visibleFrame.width ?? 800 * 0.9, 
                     height: NSScreen.main?.visibleFrame.height ?? 600 * 0.9)
        .windowResizability(.contentSize)
    }
}
