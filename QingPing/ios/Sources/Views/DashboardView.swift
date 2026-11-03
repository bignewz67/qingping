//
//  DashboardView.swift
//  清屏
//

import SwiftUI
import Charts

struct DashboardView: View {

    @EnvironmentObject private var store: StatsStore
    @State private var showLimits = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    heroCard
                    quickTiles
                    if store.hasLiveData {
                        trendCard
                    }
                    topAppsCard
                    recentCard
                    capabilityNote
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 30)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("清屏")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        store.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
            }
            .refreshable { store.refresh() }
            .sheet(isPresented: $showLimits) {
                NavigationStack { LimitsView() }
            }
        }
    }

    // MARK: Hero

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(store.hasLiveData ? Color.white : Color.white.opacity(0.65))
                        .frame(width: 6, height: 6)
                    Text(store.hasLiveData ? "防护运行中" : "演示数据")
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.18), in: Capsule())
                .foregroundColor(.white)

                Spacer()

                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.75))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(store.snapshot.todayCount)")
                        .font(.system(size: 54, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("次")
                        .font(.title3.weight(.semibold))
                        .opacity(0.8)
                }
                Text("今日已拦截 · 累计 \(store.snapshot.totalCount) 次，覆盖 \(store.snapshot.appCount) 个应用")
                    .font(.footnote)
                    .opacity(0.88)
                    .lineLimit(2)
            }
            .foregroundColor(.white)

            HStack(spacing: 10) {
                heroPill(title: "开屏跳过", value: store.snapshot.splashCount, symbol: "forward.end.fill")
                heroPill(title: "误触拦截", value: store.snapshot.misclickCount, symbol: "hand.raised.fill")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.qpHero)
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 170, height: 170)
                .offset(x: 56, y: -70)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: Color.qpBlue.opacity(0.22), radius: 18, y: 10)
    }

    private func heroPill(title: String, value: Int, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
            VStack(alignment: .leading, spacing: 0) {
                Text("\(value)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(title)
                    .font(.system(size: 10))
                    .opacity(0.82)
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.16),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: 概览

    private var quickTiles: some View {
        HStack(spacing: 10) {
            StatTile(title: "累计拦截",
                     value: "\(store.snapshot.totalCount)",
                     symbol: "shield.checkered",
                     tint: .qpTeal)
            StatTile(title: "覆盖应用",
                     value: "\(store.snapshot.appCount)",
                     symbol: "square.grid.2x2",
                     tint: .qpBlue)
            StatTile(title: "日均拦截",
                     value: "\(store.snapshot.avgPerDay)",
                     symbol: "chart.bar",
                     tint: .qpViolet)
        }
    }

    // MARK: 趋势

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "近 7 天", subtitle: "近 7 天共 \(store.snapshot.weeklyCount) 次")
            Chart(store.snapshot.daily) { point in
                BarMark(
                    x: .value("日期", point.date, unit: .day),
                    y: .value("拦截", point.count)
                )
                .foregroundStyle(Color.qpAccent)
                .cornerRadius(5)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .frame(height: 152)
        }
        .qpCard()
    }

    // MARK: Top Apps

    private var topAppsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "拦截最多", subtitle: "前 3 名")

            if store.snapshot.apps.isEmpty {
                EmptyHint(symbol: "tray",
                          title: "还没有拦截记录",
                          message: "打开其它 App 触发开屏广告后，这里会自动出现统计。")
            } else {
                let maxCount = max(store.snapshot.sortedApps.first?.total ?? 1, 1)
                ForEach(Array(store.snapshot.sortedApps.prefix(3)), id: \.bundleID) { app in
                    HStack(spacing: 12) {
                        AppMonogram(name: app.name, bundleID: app.bundleID, size: 38)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(app.name)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                Spacer()
                                Text("\(app.total)")
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                            }
                            ratioBar(ratio: Double(app.total) / Double(maxCount))
                        }
                    }
                }
            }
        }
        .qpCard()
    }

    private func ratioBar(ratio: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.06))
                Capsule()
                    .fill(Color.qpAccent)
                    .frame(width: max(6, proxy.size.width * min(max(ratio, 0), 1)))
            }
        }
        .frame(height: 6)
    }

    // MARK: 最近拦截

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "最近拦截", subtitle: "最新 5 条")

            let events = Array(store.snapshot.recentEvents.prefix(5))
            if events.isEmpty {
                EmptyHint(symbol: "clock",
                          title: "暂无记录",
                          message: "拦截事件会实时汇总到这里。")
            } else {
                ForEach(events) { event in
                    HStack(spacing: 12) {
                        AppMonogram(name: event.appName, bundleID: event.bundleID, size: 34)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(event.appName)
                                .font(.subheadline.weight(.medium))
                            Text(event.detail.isEmpty ? event.kind.title : event.detail)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 4) {
                            KindBadge(kind: event.kind)
                            Text(event.date, style: .relative)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .qpCard()
    }

    // MARK: 说明

    private var capabilityNote: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                Text("数据来自系统级注入，非越狱环境无法产生真实拦截")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Button {
                showLimits = true
            } label: {
                HStack(spacing: 4) {
                    Text("了解 iOS 限制与权限")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .font(.caption.weight(.medium))
                .foregroundColor(.qpBlue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }
}
