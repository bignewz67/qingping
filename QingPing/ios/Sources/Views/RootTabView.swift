//
//  RootTabView.swift
//  清屏
//

import SwiftUI

struct RootTabView: View {

    @EnvironmentObject private var store: StatsStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("概览", systemImage: "shield.lefthalf.filled") }

            AppsView()
                .tabItem { Label("应用", systemImage: "square.grid.2x2") }

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .tint(Color.qpTeal)
        .onAppear { store.refresh() }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                store.refresh()
            }
        }
    }
}
