//
//  QingPingApp.swift
//  清屏 · iOS 16.0+
//

import SwiftUI

@main
struct QingPingApp: App {

    @StateObject private var statsStore = StatsStore()
    @StateObject private var prefsStore = PrefsStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(statsStore)
                .environmentObject(prefsStore)
        }
    }
}
