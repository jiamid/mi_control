import SwiftUI

/// RC003 指示图 + 左右正交折线（每条线独立竖槽，避免重叠）。
struct RemoteControlDiagram<PopoverContent: View>: View {
    @Binding var selectedButton: RemoteButton
    @Binding var showMappingPopover: Bool
    let voiceActive: Bool
    let actionLabel: (RemoteButton) -> String
    @ViewBuilder let mappingPopover: () -> PopoverContent

    private let canvasWidth: CGFloat = 820
    private let canvasHeight: CGFloat = 520
    private let remoteHeight: CGFloat = 470
    private let remoteWidth: CGFloat = 470 * LogoRC003Metrics.aspect
    private let labelWidth: CGFloat = 176
    private let labelMargin: CGFloat = 10
    private let corridorInset: CGFloat = 10
    private let laneGap: CGFloat = 7

    var body: some View {
        let remoteRect = CGRect(
            x: (canvasWidth - remoteWidth) / 2,
            y: (canvasHeight - remoteHeight) / 2,
            width: remoteWidth,
            height: remoteHeight
        )
        let callouts = makeCallouts(remoteRect: remoteRect)
        let popoverPoint = absoluteAnchor(for: selectedButton, in: remoteRect)
        let arrowEdge: Edge = popoverPoint.x < remoteRect.midX ? .leading : .trailing

        return VStack(spacing: 10) {
            ZStack {
                ForEach(callouts) { item in
                    let selected = item.button.map { selectedButton == $0 } ?? false
                    let mic = item.button == nil
                    CalloutLine(anchor: item.anchor, end: item.end, laneX: item.laneX)
                        .stroke(
                            strokeColor(selected: selected, mic: mic),
                            style: StrokeStyle(lineWidth: selected ? 2 : 1.2, lineCap: .round, lineJoin: .round)
                        )
                        .allowsHitTesting(false)

                    Circle()
                        .fill(strokeColor(selected: selected, mic: mic))
                        .frame(width: selected ? 6 : 4.5, height: selected ? 6 : 4.5)
                        .position(item.anchor)
                        .allowsHitTesting(false)
                }

                LogoRC003RemoteView(
                    selectedButton: selectedButton,
                    voiceActive: voiceActive,
                    onSelect: { button in
                        activate(button)
                    }
                )
                .frame(width: remoteWidth, height: remoteHeight)
                .position(x: remoteRect.midX, y: remoteRect.midY)

                ForEach(callouts) { item in
                    calloutChip(item)
                        .frame(width: item.labelRect.width, height: item.labelRect.height)
                        .position(x: item.labelRect.midX, y: item.labelRect.midY)
                }

                // 弹层锚在当前按键中心，避免整块图表右侧弹出
                Color.clear
                    .frame(width: 1, height: 1)
                    .position(popoverPoint)
                    .popover(isPresented: $showMappingPopover, arrowEdge: arrowEdge) {
                        mappingPopover()
                            .frame(width: 360)
                            .padding(14)
                    }
            }
            .frame(width: canvasWidth, height: canvasHeight)

            Text("点击左右标签或遥控按键修改映射 · 麦克风固定为系统听写")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    private func activate(_ button: RemoteButton) {
        selectedButton = button
        showMappingPopover = true
    }

    private func absoluteAnchor(for button: RemoteButton, in remoteRect: CGRect) -> CGPoint {
        let unit = LogoRC003Metrics.anchor(for: button)
        return CGPoint(
            x: remoteRect.minX + unit.x * remoteRect.width,
            y: remoteRect.minY + unit.y * remoteRect.height
        )
    }

    /// 标签贴近锚点 Y 并防重叠；每条折线独占一条竖槽。
    private func makeCallouts(remoteRect: CGRect) -> [CalloutItem] {
        let specs: [(RemoteButton?, String, CalloutSide, CGPoint)] = [
            (.power, "电源", .left, LogoRC003Metrics.anchor(for: .power)),
            (nil, "麦克风", .right, LogoRC003Metrics.micAnchor),
            (.up, "上", .left, LogoRC003Metrics.anchor(for: .up)),
            (.left, "左", .left, LogoRC003Metrics.anchor(for: .left)),
            (.right, "右", .right, LogoRC003Metrics.anchor(for: .right)),
            (.ok, "OK", .right, LogoRC003Metrics.anchor(for: .ok)),
            (.down, "下", .left, LogoRC003Metrics.anchor(for: .down)),
            (.back, "返回", .left, LogoRC003Metrics.anchor(for: .back)),
            (.volumeUp, "音量+", .right, LogoRC003Metrics.anchor(for: .volumeUp)),
            (.home, "主页", .left, LogoRC003Metrics.anchor(for: .home)),
            (.volumeDown, "音量−", .right, LogoRC003Metrics.anchor(for: .volumeDown)),
            (.menu, "菜单", .left, LogoRC003Metrics.anchor(for: .menu)),
            (.tv, "TV", .right, LogoRC003Metrics.anchor(for: .tv)),
        ]

        func absolute(_ unit: CGPoint) -> CGPoint {
            CGPoint(
                x: remoteRect.minX + unit.x * remoteRect.width,
                y: remoteRect.minY + unit.y * remoteRect.height
            )
        }

        func column(_ side: CalloutSide) -> [CalloutItem] {
            let rows = specs
                .filter { $0.2 == side }
                .sorted { absolute($0.3).y < absolute($1.3).y }
            let count = rows.count
            guard count > 0 else { return [] }

            let rowH = min(44, (canvasHeight - labelMargin * 2 - 4 * CGFloat(count - 1)) / CGFloat(count))
            let labelX: CGFloat = side == .left ? labelMargin : canvasWidth - labelWidth - labelMargin

            var tops: [CGFloat] = rows.map { spec in
                let ay = absolute(spec.3).y
                return min(max(ay - rowH / 2, labelMargin), canvasHeight - labelMargin - rowH)
            }
            for i in 1..<count {
                let minTop = tops[i - 1] + rowH + 4
                if tops[i] < minTop { tops[i] = minTop }
            }
            if let last = tops.last, last + rowH > canvasHeight - labelMargin {
                let overflow = last + rowH - (canvasHeight - labelMargin)
                for i in 0..<count { tops[i] -= overflow }
            }
            for i in stride(from: count - 2, through: 0, by: -1) {
                let maxTop = tops[i + 1] - rowH - 4
                if tops[i] > maxTop { tops[i] = maxTop }
            }
            if tops[0] < labelMargin {
                let shift = labelMargin - tops[0]
                for i in 0..<count { tops[i] += shift }
            }

            let corridorLeft = side == .left
                ? labelX + labelWidth + corridorInset
                : remoteRect.maxX + corridorInset
            let corridorRight = side == .left
                ? remoteRect.minX - corridorInset
                : labelX - corridorInset
            let corridorW = max(corridorRight - corridorLeft, CGFloat(count) * laneGap)
            let step = count == 1 ? 0 : (corridorW - laneGap) / CGFloat(count - 1)

            return rows.enumerated().map { index, spec in
                let anchor = absolute(spec.3)
                let labelRect = CGRect(x: labelX, y: tops[index], width: labelWidth, height: rowH)
                let end = CGPoint(
                    x: side == .left ? labelRect.maxX : labelRect.minX,
                    y: labelRect.midY
                )
                let laneX: CGFloat = side == .left
                    ? corridorRight - laneGap / 2 - CGFloat(index) * step
                    : corridorLeft + laneGap / 2 + CGFloat(index) * step
                return CalloutItem(
                    id: spec.0?.rawValue ?? "mic",
                    button: spec.0,
                    title: spec.1,
                    side: side,
                    anchor: anchor,
                    end: end,
                    laneX: laneX,
                    labelRect: labelRect
                )
            }
        }

        return column(.left) + column(.right)
    }

    @ViewBuilder
    private func calloutChip(_ item: CalloutItem) -> some View {
        if let button = item.button {
            let selected = selectedButton == button
            Button {
                activate(button)
            } label: {
                chipContent(
                    title: item.title,
                    detail: actionLabel(button),
                    selected: selected,
                    accent: .accentColor
                )
            }
            .buttonStyle(.plain)
            .help(button.displayName)
        } else {
            chipContent(
                title: item.title,
                detail: voiceActive ? "听写中" : "系统听写（固定）",
                selected: voiceActive,
                accent: .orange
            )
            .help("按住遥控器麦克风：系统听写并粘贴")
        }
    }

    private func chipContent(
        title: String,
        detail: String,
        selected: Bool,
        accent: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(selected ? accent : .primary)
            Text(detail)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? accent.opacity(0.12) : Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(selected ? accent.opacity(0.55) : Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private func strokeColor(selected: Bool, mic: Bool) -> Color {
        if mic { return Color.orange.opacity(voiceActive ? 0.9 : 0.45) }
        return selected ? Color.accentColor : Color.secondary.opacity(0.5)
    }
}

// MARK: - Callout primitives

private enum CalloutSide {
    case left, right
}

private struct CalloutItem: Identifiable {
    let id: String
    let button: RemoteButton?
    let title: String
    let side: CalloutSide
    let anchor: CGPoint
    let end: CGPoint
    let laneX: CGFloat
    let labelRect: CGRect
}

/// 正交折线：锚点 → 独占竖槽 → 标签边。
private struct CalloutLine: Shape {
    var anchor: CGPoint
    var end: CGPoint
    var laneX: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: anchor)
        path.addLine(to: CGPoint(x: laneX, y: anchor.y))
        path.addLine(to: CGPoint(x: laneX, y: end.y))
        path.addLine(to: end)
        return path
    }
}
