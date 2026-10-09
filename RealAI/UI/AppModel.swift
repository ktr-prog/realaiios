import Foundation
import SwiftUI
import AVFoundation

enum AppScreen {
    case chat
    case tips
    case thoughts
    case wordFix
    case delay
    case responses
}

enum FaceState {
    case neutral
    case encourage
    case discourage

    var imageName: String {
        switch self {
        case .neutral: return "face_neutral"
        case .encourage: return "face_encourage"
        case .discourage: return "face_discourage"
        }
    }
}

enum AlertKind {
    case erase
    case advanced
    case erased
}

/// Port der Zustands- und Ablauflogik aus MainActivity.java.
@MainActor
final class AppModel: ObservableObject {
    let engine = RealAIEngine()

    @Published var screen: AppScreen = .tips          // Die Android-App zeigt beim Start die Tipps (DisplayTips)
    @Published var historyLines: [String] = []
    @Published var thoughtLines: [String] = []
    @Published var wordList: [String] = []
    @Published var input: String = ""
    @Published var face: FaceState = .neutral
    @Published var alertKind: AlertKind? = nil

    @Published var advanced = false
    @Published var speechEnabled = false
    @Published var topicBased = true
    @Published var conditionBased = true
    @Published var proceduralBased = true
    @Published var delaySelection = 0

    // Timer-Zustand (int_Time, bl_DelayForever, int_Delay, bl_Bored, bl_Typing)
    private var intTime = 10000
    private var delayForever = false
    private var intDelay = 0
    private var bored = false
    private var typing = false
    private var sending = false
    private var started = false

    private var timerTask: Task<Void, Never>?
    private var thinkTask: Task<Void, Never>?
    private let synthesizer = AVSpeechSynthesizer()

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback)
    }

    // MARK: - Start

    func start() async {
        if started {
            return
        }
        started = true
        let s = await engine.load()
        apply(s)
        await refreshHistory()
    }

    private func apply(_ s: EngineSettings) {
        advanced = s.advanced
        speechEnabled = s.speech
        topicBased = s.topicBased
        conditionBased = s.conditionBased
        proceduralBased = s.proceduralBased

        switch s.delay {
        case "20 seconds":
            delaySelection = 1
            intTime = 20000
            delayForever = false
        case "30 seconds":
            delaySelection = 2
            intTime = 30000
            delayForever = false
        case "Infinite":
            delaySelection = 3
            delayForever = true
        default:
            delaySelection = 0
            intTime = 10000
            delayForever = false
        }
    }

    func scenePhaseChanged(_ phase: ScenePhase) {
        if phase == .active {
            if screen == .chat && input.isEmpty {
                startTimer()
                startThinking()
            } else if screen == .thoughts {
                startThinking()
            }
        } else if phase == .background {
            stopTimer()
            stopThinking()
        }
    }

    // MARK: - Anzeige aktualisieren (ScrollHistory / ScrollThoughts)

    func refreshHistory() async {
        historyLines = await engine.historyLines()
        face = .neutral
        if bored {
            bored = false
        }
    }

    func refreshThoughts() async {
        thoughtLines = await engine.thoughtLines()
    }

    // MARK: - Timer (Aufmerksamkeitsspanne)

    private func startTimer() {
        stopTimer()
        intDelay = 0
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { return }
                self.timerTick()
                let ms = self.intTime
                try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
            }
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    private func timerTick() {
        if !bored {
            if intDelay == 0 {
                intDelay += 1
            } else if intDelay == 1 && !delayForever {
                bored = true
                attentionSpan()
                intDelay = 0
            }
        }
    }

    private func attentionSpan() {
        if !typing {
            Task {
                let output = await engine.attentionSpan()
                if !output.isEmpty {
                    await refreshHistory()
                }
            }
        }
    }

    // MARK: - Denken

    private func startThinking() {
        stopThinking()
        thinkTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { return }
                _ = await self.engine.thinkStep()
                if self.screen == .thoughts {
                    await self.refreshThoughts()
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func stopThinking() {
        thinkTask?.cancel()
        thinkTask = nil
    }

    // MARK: - Eingabe

    func inputChanged() {
        if screen != .chat {
            return
        }
        face = .neutral
        if input.isEmpty {
            typing = false
            startTimer()
            startThinking()
        } else {
            typing = true
            Task { await engine.setInitiation(false) }
            stopTimer()
            stopThinking()
        }
    }

    func send() {
        let text = input
        if text.isEmpty || sending {
            return
        }
        sending = true
        Task {
            if let output = await engine.handleUserInput(text) {
                if speechEnabled && !output.isEmpty {
                    speak(output)
                }
                await refreshHistory()
                input = ""
            }
            sending = false
        }
    }

    private func speak(_ text: String) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        try? AVAudioSession.sharedInstance().setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }

    // MARK: - Encourage / Discourage / New Session

    func encourage() {
        Task {
            await engine.encourage()
            await refreshHistory()
            face = .encourage
            try? await Task.sleep(nanoseconds: 700_000_000)
            face = .neutral
        }
    }

    func discourage() {
        Task {
            await engine.discourage()
            await refreshHistory()
            face = .discourage
            try? await Task.sleep(nanoseconds: 700_000_000)
            face = .neutral
        }
    }

    func newSession() {
        Task {
            await engine.newSession()
            await refreshHistory()
        }
    }

    // MARK: - Bildschirme öffnen / schließen

    func openTips() {
        stopTimer()
        stopThinking()
        screen = .tips
    }

    func closeTips() {
        screen = .chat
        Task { await refreshHistory() }
        startTimer()
        startThinking()
    }

    func openThoughts() {
        stopTimer()
        screen = .thoughts
        startThinking()
        Task { await refreshThoughts() }
    }

    func openWordFix() {
        Task {
            let words = await engine.allWords()
            if words.isEmpty {
                return
            }
            wordList = words
            stopTimer()
            stopThinking()
            screen = .wordFix
        }
    }

    func openDelay() {
        stopTimer()
        stopThinking()
        screen = .delay
    }

    func openResponses() {
        stopTimer()
        stopThinking()
        screen = .responses
    }

    /// CloseThought / CloseWordFix: zurück zum Chat.
    func closeSubScreen() {
        screen = .chat
        Task { await refreshHistory() }
        startTimer()
        startThinking()
    }

    // MARK: - Word Fix / Delay / Antwortarten

    func applyWordFix(index: Int, newWord: String) async {
        await engine.wordFix(index: index, newWord: newWord)
        closeSubScreen()
    }

    func applyDelay(selection: Int) {
        delaySelection = selection
        let text: String
        if selection == 3 {
            text = "Infinite"
            delayForever = true
        } else {
            let seconds = (selection * 10) + 10
            text = "\(seconds) seconds"
            intTime = seconds * 1000
            delayForever = false
        }
        Task { await engine.setDelay(text) }
        closeSubScreen()
    }

    /// index: 0 = Topic, 1 = Condition, 2 = Procedural
    func setResponseMethod(_ index: Int, _ value: Bool) {
        if index == 0 {
            topicBased = value
        } else if index == 1 {
            conditionBased = value
        } else if index == 2 {
            proceduralBased = value
        }
        Task { await engine.setResponseMethod(index: index, value: value) }
    }

    // MARK: - Schalter und Bestätigungen

    func toggleSpeech() {
        speechEnabled.toggle()
        let value = speechEnabled
        Task { await engine.setSpeech(value) }
    }

    func toggleAdvanced() {
        if advanced {
            setAdvanced(false)
        } else {
            stopTimer()
            alertKind = .advanced
        }
    }

    private func setAdvanced(_ value: Bool) {
        advanced = value
        Task { await engine.setAdvanced(value) }
    }

    func requestErase() {
        stopTimer()
        alertKind = .erase
    }

    func confirmAdvanced() {
        setAdvanced(true)
        resumeAfterDialog()
    }

    func confirmErase() {
        Task {
            await engine.eraseMemory()
            historyLines = []
            thoughtLines = []
            input = ""
            try? await Task.sleep(nanoseconds: 400_000_000)
            alertKind = .erased
        }
    }

    func cancelDialog() {
        resumeAfterDialog()
    }

    func resumeAfterDialog() {
        if screen == .chat && input.isEmpty {
            startTimer()
            startThinking()
        }
    }
}
