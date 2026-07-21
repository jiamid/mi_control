import AVFoundation
import Foundation
import Speech

/// 把 RC003 解码后的 PCM 直接送入系统 SFSpeechRecognizer。
final class DirectSpeechTranscriber {
    private let queue = DispatchQueue(label: "com.jiamid.MiControlApp.speech")
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var format: AVAudioFormat?
    private var bestText = ""
    private var finalEmitted = false
    private var active = false
    private var localeIdentifier = "zh-CN"
    private var pendingStartLocale: String?

    var onPartial: ((String) -> Void)?
    var onFinal: ((String) -> Void)?
    var onStatus: ((String) -> Void)?

    static var authorizationStatus: SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }

    static var isAuthorized: Bool {
        authorizationStatus == .authorized
    }

    /// 请求语音识别权限。已授权立刻回调 true；拒绝为 false；首次弹窗后按结果回调。
    static func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        let current = authorizationStatus
        switch current {
        case .authorized:
            completion?(true)
            return
        case .denied, .restricted:
            AppLogger.shared.write("SPEECH auth=\(current.rawValue) blocked")
            completion?(false)
            return
        case .notDetermined:
            break
        @unknown default:
            break
        }

        SFSpeechRecognizer.requestAuthorization { status in
            AppLogger.shared.write("SPEECH auth=\(status.rawValue)")
            DispatchQueue.main.async {
                completion?(status == .authorized)
            }
        }
    }

    @discardableResult
    static func requestAuthorization() -> Bool {
        requestAuthorization(completion: nil)
        return isAuthorized
    }

    func start(localeIdentifier: String = "zh-CN") {
        queue.async { [weak self] in
            guard let self else { return }
            self.stopLocked(emitFinal: false)
            self.localeIdentifier = localeIdentifier.isEmpty ? "zh-CN" : localeIdentifier
            self.bestText = ""
            self.finalEmitted = false
            self.active = true

            switch Self.authorizationStatus {
            case .authorized:
                self.beginRecognitionLocked()
            case .denied, .restricted:
                self.active = false
                DispatchQueue.main.async {
                    self.onStatus?("语音识别被拒绝：请在系统设置 → 隐私 → 语音识别中勾选本应用")
                }
                AppLogger.shared.write("SPEECH denied")
            case .notDetermined:
                // 已授权但状态偶发延迟、或首次弹窗：先挂起本次，授权完成后再开听写
                self.pendingStartLocale = self.localeIdentifier
                DispatchQueue.main.async {
                    self.onStatus?("正在请求语音识别权限…")
                }
                AppLogger.shared.write("SPEECH auth_pending")
                Self.requestAuthorization { [weak self] granted in
                    guard let self else { return }
                    self.queue.async {
                        guard self.active, granted else {
                            if !granted {
                                self.active = false
                                DispatchQueue.main.async {
                                    self.onStatus?("语音识别未授权")
                                }
                            }
                            return
                        }
                        self.beginRecognitionLocked()
                    }
                }
            @unknown default:
                self.active = false
                DispatchQueue.main.async {
                    self.onStatus?("语音识别状态未知")
                }
            }
        }
    }

    private func beginRecognitionLocked() {
        pendingStartLocale = nil
        let candidates = [
            Locale(identifier: localeIdentifier),
            Locale(identifier: "zh-CN"),
            Locale(identifier: "zh-Hans"),
            Locale.current,
        ]
        var chosen: SFSpeechRecognizer?
        for locale in candidates {
            if let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable {
                chosen = recognizer
                localeIdentifier = locale.identifier
                break
            }
        }
        guard let recognizer = chosen else {
            active = false
            DispatchQueue.main.async {
                self.onStatus?("当前系统无可用的中文听写引擎")
            }
            AppLogger.shared.write("SPEECH recognizer_unavailable")
            return
        }
        self.recognizer = recognizer

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        ) else {
            active = false
            DispatchQueue.main.async {
                self.onStatus?("音频格式初始化失败")
            }
            return
        }
        self.format = format

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            self.queue.async {
                if let result {
                    let text = result.bestTranscription.formattedString
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        self.bestText = text
                        if result.isFinal {
                            if !self.finalEmitted {
                                self.finalEmitted = true
                                DispatchQueue.main.async { self.onFinal?(text) }
                            }
                        } else {
                            DispatchQueue.main.async { self.onPartial?(text) }
                        }
                    }
                }
                if let error {
                    let message = error.localizedDescription
                    if !message.lowercased().contains("cancel") {
                        AppLogger.shared.write("SPEECH error=\(message)")
                        DispatchQueue.main.async {
                            self.onStatus?("听写错误：\(message)")
                        }
                    }
                }
            }
        }

        DispatchQueue.main.async {
            self.onStatus?("系统听写中（\(self.localeIdentifier)）")
        }
        AppLogger.shared.write("SPEECH start locale=\(localeIdentifier)")
    }

    func append(samples: [Int16]) {
        queue.async { [weak self] in
            guard let self, self.active, let request = self.request, let format = self.format else {
                return
            }
            guard !samples.isEmpty else { return }
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(samples.count)
            ) else { return }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { src in
                guard let base = src.baseAddress,
                      let dst = buffer.int16ChannelData?[0]
                else { return }
                dst.update(from: base, count: samples.count)
            }
            request.append(buffer)
        }
    }

    /// 结束本次按住说话；返回最终文本（可能为空）。
    func stop(completion: @escaping (String) -> Void) {
        queue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { completion("") }
                return
            }
            self.stopLocked(emitFinal: true, completion: completion)
        }
    }

    private func stopLocked(emitFinal: Bool, completion: ((String) -> Void)? = nil) {
        guard active || request != nil else {
            if emitFinal {
                DispatchQueue.main.async { completion?("") }
            }
            return
        }
        active = false
        pendingStartLocale = nil
        request?.endAudio()
        AppLogger.shared.write("SPEECH endAudio")

        let finish: () -> Void = { [weak self] in
            guard let self else {
                DispatchQueue.main.async { completion?("") }
                return
            }
            if emitFinal, !self.finalEmitted, !self.bestText.isEmpty {
                self.finalEmitted = true
                DispatchQueue.main.async { self.onFinal?(self.bestText) }
            }
            let text = self.bestText
            self.task?.cancel()
            self.task = nil
            self.request = nil
            DispatchQueue.main.async {
                completion?(text)
            }
            AppLogger.shared.write("SPEECH done chars=\(text.count)")
        }

        // Give the recognizer a short window to produce isFinal
        queue.asyncAfter(deadline: .now() + 1.2, execute: finish)
    }
}
