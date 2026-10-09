import SwiftUI

@main
struct RealAIApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .task { await model.start() }
                .onChange(of: scenePhase) { phase in
                    model.scenePhaseChanged(phase)
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            switch model.screen {
            case .chat:
                ChatView()
            case .tips:
                TipsView()
            case .thoughts:
                ThoughtsView()
            case .wordFix:
                WordFixView()
            case .delay:
                DelayView()
            case .responses:
                ResponsesView()
            }
        }
        .alert("System Message",
               isPresented: Binding(
                get: { model.alertKind != nil },
                set: { newValue in
                    if !newValue {
                        model.alertKind = nil
                    }
                }),
               presenting: model.alertKind) { kind in
            alertButtons(kind)
        } message: { kind in
            Text(alertMessage(kind))
        }
    }

    @ViewBuilder
    private func alertButtons(_ kind: AlertKind) -> some View {
        switch kind {
        case .erase:
            Button("Yes", role: .destructive) { model.confirmErase() }
            Button("No", role: .cancel) { model.cancelDialog() }
        case .advanced:
            Button("Yes") { model.confirmAdvanced() }
            Button("No", role: .cancel) { model.cancelDialog() }
        case .erased:
            Button("Ok") { model.resumeAfterDialog() }
        }
    }

    private func alertMessage(_ kind: AlertKind) -> String {
        switch kind {
        case .erase:
            return "Erase all memory?"
        case .advanced:
            return "Warning: Advanced mode will force the AI to only use procedurally generated responses and allow its thinking to modify its brain. This mode is not recommended and should only be used for the sake of science. Are you sure you want to enable this?"
        case .erased:
            return "Brain has been erased."
        }
    }
}

struct ChatView: View {
    @EnvironmentObject var model: AppModel

    private var speechTitle: String {
        return "Speech: " + (model.speechEnabled ? "true" : "false")
    }

    private var advancedTitle: String {
        return "Advanced Mode: " + (model.advanced ? "true" : "false")
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button("Discourage") { model.discourage() }
                    .buttonStyle(.bordered)
                Spacer()
                Image(model.face.imageName)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 48, height: 48)
                Spacer()
                Button("Encourage") { model.encourage() }
                    .buttonStyle(.bordered)
            }

            historyView

            TextField("", text: $model.input)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.send)
                .autocorrectionDisabled()
                .onSubmit { model.send() }

            Button {
                model.send()
            } label: {
                Text("Enter").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Menu {
                Button("New Session") { model.newSession() }
                Button("Thoughts") { model.openThoughts() }
                Button("Tips") { model.openTips() }
                Button("Word Fix") { model.openWordFix() }
                Button("Set Delay") { model.openDelay() }
                Button("Response Types") { model.openResponses() }
                Button(speechTitle) { model.toggleSpeech() }
                Button(advancedTitle) { model.toggleAdvanced() }
                Button("Erase Memory", role: .destructive) { model.requestErase() }
            } label: {
                Text("Menu")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
            }
        }
        .padding()
        .onChange(of: model.input) { _ in
            model.inputChanged()
        }
    }

    private var historyView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(model.historyLines.enumerated()), id: \.offset) { item in
                        Text(item.element)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(8)
            }
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)
            .onChange(of: model.historyLines) { _ in
                withAnimation {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onAppear {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }
}
