//
//  AppsView.swift
//  清屏
//

import SwiftUI

struct AppsView: View {

    @EnvironmentObject private var store: StatsStore
    @State private var query = ""

    private var filteredApps: [AppStats] {
        let list = store.snapshot.sortedApps
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return list }
        return list.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.bundleID.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if store.snapshot.isDemo {
                    Section {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "flask")
                                .foregroundColor(.qpAmber)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("当前为演示数据")
                                    .font(.subheadline.weight(.semibold))
                                Text("没读到注入端统计。请确认：已用 TrollFools 把 QingPing.dylib 注入目标 App，且清屏有平台权限（见 README 第五、七节）。")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                Section {
                    if filteredApps.isEmpty {
                        EmptyHint(symbol: "magnifyingglass",
                                  title: "没有匹配的应用",
                                  message: "换个关键词试试，或先用其它 App 触发一次开屏广告。")
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                    } else {
                        ForEach(filteredApps) { app in
                            NavigationLink(value: app) {
                                AppRow(app: app)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("按应用统计")
                        Spacer()
                        Text("\(filteredApps.count) 个")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("应用")
            .searchable(text: $query,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "搜索应用名 / Bundle ID")
            .navigationDestination(for: AppStats.self) { app in
                AppDetailView(app: app)
            }
        }
    }
}

struct AppRow: View {
    let app: AppStats

    var body: some View {
        HStack(spacing: 12) {
            AppMonogram(name: app.name, bundleID: app.bundleID, size: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(app.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(app.bundleID)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                if app.isInjectedOnly {
                    Text("已注入")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(Color.qpBlue)
                } else {
                    Text("\(app.total)")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                if let last = app.lastSeen {
                    Text(last, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 详情

struct AppDetailView: View {

    let app: AppStats
    @EnvironmentObject private var store: StatsStore

    private var events: [InterceptEvent] {
        store.snapshot.events(for: app.bundleID)
    }

    private var liveApp: AppStats {
        store.snapshot.app(for: app.bundleID) ?? app
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    AppMonogram(name: liveApp.name, bundleID: liveApp.bundleID, size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(liveApp.name)
                            .font(.title3.weight(.semibold))
                        Text(liveApp.bundleID)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        if let last = liveApp.lastSeen {
                            Text("最近拦截：\(last.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 6)
            }

            Section("拦截构成") {
                HStack(spacing: 10) {
                    StatTile(title: "开屏跳过",
                             value: "\(liveApp.splash)",
                             symbol: "forward.end.fill",
                             tint: .qpTeal)
                    StatTile(title: "误触拦截",
                             value: "\(liveApp.misclick)",
                             symbol: "hand.raised.fill",
                             tint: .qpAmber)
                    StatTile(title: "合计",
                             value: "\(liveApp.total)",
                             symbol: "sum",
                             tint: .qpBlue)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                .listRowBackground(Color.clear)
            }

            Section("最近事件") {
                if events.isEmpty {
                    Text("暂无事件记录（注入端只保留最近 120 条）")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(events.prefix(20)) { event in
                        HStack(spacing: 10) {
                            KindBadge(kind: event.kind)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.detail.isEmpty ? event.kind.title : event.detail)
                                    .font(.caption)
                                    .lineLimit(1)
                                Text(event.date.formatted(date: .abbreviated, time: .standard))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(liveApp.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
