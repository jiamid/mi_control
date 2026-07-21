import AppKit
import Combine
import SwiftUI

/// 屏幕中央的听写浮层：声波动画 + 实时识别文字。
final class SpeechOverlayController {
    static let shared = SpeechOverlayController()

    private var panel: NSPanel?
    private var hosting: NSHostingView<SpeechOverlayView>?
    private let model = SpeechOverlayModel()

    private init() {}

    func show() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.model.resetForSession()
            self.ensurePanel()
            guard let panel = self.panel else { return }
            self.positionCentered(panel)
            if !panel.isVisible {
                panel.orderFrontRegardless()
            }
            self.model.isVisible = true
        }
    }

    func update(transcript: String, audioLevel: Double) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.model.transcript = transcript
            self.model.audioLevel = min(1, max(0, audioLevel))
            if self.model.isVisible, let panel = self.panel {
                self.ensurePanel()
                self.positionCentered(panel)
            }
        }
    }

    func hide(after delay: TimeInterval = 0.15) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.model.isVisible = false
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, !self.model.isVisible else { return }
                self.panel?.orderOut(nil)
            }
        }
    }

    private func ensurePanel() {
        if panel != nil {
            hosting?.rootView = SpeechOverlayView(model: model)
            return
        }

        let view = SpeechOverlayView(model: model)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 420, height: 148)

        let panel = NSPanel(
            contentRect: host.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true

        self.hosting = host
        self.panel = panel
    }

    private func positionCentered(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        // 水平居中，垂直偏下（约在下三分之一处），避免挡住中间编辑区
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.minY + visible.height * 0.18
        )
        panel.setFrameOrigin(origin)
    }
}

final class SpeechOverlayModel: ObservableObject {
    @Published var isVisible = false
    @Published var transcript = ""
    @Published var audioLevel: Double = 0

    func resetForSession() {
        transcript = ""
        audioLevel = 0
        isVisible = true
    }
}

struct SpeechOverlayView: View {
    @ObservedObject var model: SpeechOverlayModel
    @State private var tick: TimeInterval = 0

    private let barCount = 24

    var body: some View {
        VStack(spacing: 12) {
            SoundWaveBars(barCount: barCount, level: model.audioLevel, time: tick)
                .frame(height: 40)

            Text(displayText)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
                .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .top)
                .animation(.easeOut(duration: 0.12), value: model.transcript)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(width: 420)
        .opacity(model.isVisible ? 1 : 0)
        .scaleEffect(model.isVisible ? 1 : 0.98)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: model.isVisible)
        .onReceive(timer) { date in
            guard model.isVisible else { return }
            tick = date.timeIntervalSinceReferenceDate
        }
    }

    private var timer: Publishers.Autoconnect<Timer.TimerPublisher> {
        Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()
    }

    private var displayText: String {
        let text = model.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "开始说话…" : text
    }
}

private struct SoundWaveBars: View {
    let barCount: Int
    let level: Double
    let time: TimeInterval

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white,
                                Color(red: 0.55, green: 0.82, blue: 1.0),
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
                    .frame(width: 5, height: barHeight(for: index))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func barHeight(for index: Int) -> CGFloat {
        let center = Double(barCount - 1) / 2
        let distance = abs(Double(index) - center) / max(center, 1)
        let envelope = 1 - distance * 0.55
        let wave = sin((Double(index) * 0.55) + time * 6.2)
        let idle = 0.18 + 0.14 * (wave * 0.5 + 0.5)
        let active = idle + level * (0.55 + 0.35 * envelope)
        return max(6, CGFloat(active) * 44)
    }
}
