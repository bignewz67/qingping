//
//  Theme.swift
//  清屏
//

import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }

    static let qpTeal   = Color(hex: 0x14C8A6)
    static let qpBlue   = Color(hex: 0x2D7FF9)
    static let qpAmber  = Color(hex: 0xF2A93B)
    static let qpViolet = Color(hex: 0x7C5CFC)
    static let qpRose   = Color(hex: 0xEC4899)

    static var qpHero: LinearGradient {
        LinearGradient(colors: [Color(hex: 0x12C9A5), Color(hex: 0x2D7FF9)],
                       startPoint: .topLeading,
                       endPoint: .bottomTrailing)
    }

    static var qpAccent: LinearGradient {
        LinearGradient(colors: [Color.qpTeal, Color.qpBlue],
                       startPoint: .leading,
                       endPoint: .trailing)
    }
}

// MARK: - 卡片

struct QPCardModifier: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
            )
    }
}

extension View {
    func qpCard(padding: CGFloat = 16) -> some View {
        modifier(QPCardModifier(padding: padding))
    }
}

// MARK: - 通用小组件

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
            Spacer()
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct AppMonogram: View {
    let name: String
    let bundleID: String
    var size: CGFloat = 44

    private var colors: [Color] {
        let palettes: [[UInt32]] = [
            [0x14C8A6, 0x0E9F6E],
            [0x2D7FF9, 0x1D4ED8],
            [0xF2A93B, 0xEA580C],
            [0x7C5CFC, 0x4F46E5],
            [0xEC4899, 0xBE185D],
            [0x0EA5E9, 0x0369A1],
        ]
        var hash = 5381
        for byte in bundleID.utf8 {
            hash = (hash &* 33) &+ Int(byte)
        }
        let index = abs(hash) % palettes.count
        return palettes[index].map { Color(hex: $0) }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(LinearGradient(colors: colors,
                                 startPoint: .topLeading,
                                 endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(
                Text(String(name.prefix(1)))
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            )
    }
}

struct KindBadge: View {
    let kind: InterceptKind

    var color: Color {
        kind == .splash ? .qpTeal : .qpAmber
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: kind.symbol)
                .font(.system(size: 9, weight: .bold))
            Text(kind.shortTitle)
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.14), in: Capsule())
        .foregroundColor(color)
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .qpCard(padding: 12)
    }
}

struct EmptyHint: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundColor(.secondary)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .qpCard()
    }
}
