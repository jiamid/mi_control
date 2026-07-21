import AppKit
import SwiftUI

// MARK: - Logo AI 遥控器（Resources/MiControlApp-remote.png 自 logo-ai 抠出）

enum LogoRC003Metrics {
    /// 与抠图一致
    static let aspect: CGFloat = 338.0 / 886.0

    static let teal = Color(red: 0.24, green: 0.80, blue: 0.78)

    // 点位按用户反馈调整（相对抠图 0…1）
    private static let colL: CGFloat = 0.290
    private static let colR: CGFloat = 0.710
    private static let topL: CGFloat = 0.253
    private static let topR: CGFloat = 0.743
    /// 1/2 下移一点
    private static let topY: CGFloat = 0.092
    private static let padY: CGFloat = 0.317
    /// 左右方向点相对宽度的半径系数；上下用同一像素距离（× aspect）保证与左右对称
    private static let padRW: CGFloat = 0.447
    private static let dirK: CGFloat = 0.70
    private static var dirDX: CGFloat { padRW * dirK }
    private static var dirDY: CGFloat { dirDX * aspect }
    /// 8–13 上移一点点
    private static let row1: CGFloat = 0.545
    private static let row2: CGFloat = 0.675
    private static let row3: CGFloat = 0.805

    static let topDisk: CGFloat = 0.175
    static let roundDisk: CGFloat = 0.185
    static let okDisk: CGFloat = 0.28
    static let dirHit: CGFloat = 0.20

    static let micAnchor = CGPoint(x: topR, y: topY)

    static func anchor(for button: RemoteButton) -> CGPoint {
        switch button {
        case .power: return CGPoint(x: topL, y: topY)
        case .up: return CGPoint(x: 0.5, y: padY - dirDY)
        case .left: return CGPoint(x: 0.5 - dirDX, y: padY)
        case .ok: return CGPoint(x: 0.5, y: padY)
        case .right: return CGPoint(x: 0.5 + dirDX, y: padY)
        case .down: return CGPoint(x: 0.5, y: padY + dirDY)
        case .back: return CGPoint(x: colL, y: row1)
        case .volumeUp: return CGPoint(x: colR, y: row1)
        case .home: return CGPoint(x: colL, y: row2)
        case .volumeDown: return CGPoint(x: colR, y: row2)
        case .menu: return CGPoint(x: colL, y: row3)
        case .tv: return CGPoint(x: colR, y: row3)
        }
    }

    static func point(_ unit: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: unit.x * size.width, y: unit.y * size.height)
    }
}

// MARK: - Logo 遥控器图 + 热区

struct LogoRC003RemoteView: View {
    let selectedButton: RemoteButton
    let voiceActive: Bool
    let onSelect: (RemoteButton) -> Void

    var body: some View {
        GeometryReader { geo in
            let s = geo.size
            ZStack {
                remoteImage(size: s)

                hit(.power, diameter: s.width * LogoRC003Metrics.topDisk, in: s)
                micOverlay(in: s)

                ForEach([RemoteButton.up, .down, .left, .right], id: \.self) { button in
                    hit(button, diameter: s.width * LogoRC003Metrics.dirHit, in: s)
                }
                hit(.ok, diameter: s.width * LogoRC003Metrics.okDisk, in: s)

                ForEach([RemoteButton.back, .home, .menu, .tv], id: \.self) { button in
                    hit(button, diameter: s.width * LogoRC003Metrics.roundDisk, in: s)
                }

                hit(.volumeUp, diameter: s.width * LogoRC003Metrics.roundDisk, in: s)
                hit(.volumeDown, diameter: s.width * LogoRC003Metrics.roundDisk, in: s)
            }
            .frame(width: s.width, height: s.height)
        }
        .aspectRatio(LogoRC003Metrics.aspect, contentMode: .fit)
        .shadow(color: .black.opacity(0.30), radius: 12, y: 6)
    }

    private func remoteImage(size: CGSize) -> some View {
        Group {
            if let nsImage = Self.loadRemoteImage() {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: size.width * 0.12, style: .continuous)
                    .fill(Color(white: 0.82))
                    .overlay(
                        Text("缺少 MiControlApp-remote.png")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    )
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func hit(_ button: RemoteButton, diameter: CGFloat, in size: CGSize) -> some View {
        let selected = selectedButton == button
        let center = LogoRC003Metrics.point(LogoRC003Metrics.anchor(for: button), in: size)
        return Button { onSelect(button) } label: {
            Circle()
                .fill(selected ? Color.accentColor.opacity(0.40) : Color.clear)
                .overlay(
                    Circle()
                        .stroke(selected ? Color.accentColor : Color.clear, lineWidth: selected ? 2.5 : 0)
                )
                .frame(width: diameter, height: diameter)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .position(center)
    }

    private func micOverlay(in size: CGSize) -> some View {
        let d = size.width * LogoRC003Metrics.topDisk
        let center = LogoRC003Metrics.point(LogoRC003Metrics.micAnchor, in: size)
        return Circle()
            .stroke(voiceActive ? LogoRC003Metrics.teal : Color.clear, lineWidth: voiceActive ? 2.5 : 0)
            .background(Circle().fill(voiceActive ? LogoRC003Metrics.teal.opacity(0.20) : Color.clear))
            .frame(width: d, height: d)
            .position(center)
            .allowsHitTesting(false)
    }

    private static func loadRemoteImage() -> NSImage? {
        if let img = Bundle.main.image(forResource: "MiControlApp-remote") {
            return img
        }
        if let url = Bundle.main.url(forResource: "MiControlApp-remote", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        let dev = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/MiControlApp-remote.png")
        return NSImage(contentsOf: dev)
    }
}
