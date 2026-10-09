import SwiftUI

// MARK: - Tips (MainActivity.DisplayTips)

struct TipsView: View {
    @EnvironmentObject var model: AppModel

    private let tips = """
Here are some tips for teaching the AI:

1. The AI learns from observing how you respond to what it says... so, if it says "Hello." and you say "How are you?" it will learn that "How are you?" is a possible response to "Hello.". If you say something it has never seen before, it will repeat it to see how -you- would respond to it. Learning by imitation, like a young child, is not the only way it learns as you will soon discover.

2. It will generate stuff that sounds nonsensical early on... this is part of the learning process, similar to the way children phrase things in ways that don't quite make sense early on.

3. If it says something that doesn't make sense, you can discourage the AI by pressing the Discourage button. This will also reset the session so that whatever you say next won't be considered a response to what was last said.

4. In contrast to Discouraging the AI, there is a button to Encourage it and let it know it has used words properly.

5. Limit your response to a single sentence or question.

6. Use complete sentences when responding. Start with a capital letter and end with a punctuation mark.

7. Avoid contractions (use "it is" instead of "it's").

8. The AI runs in real-time and will try to initiate conversation on its own if idle for too long. To adjust how long it waits before assuming you're idle, or to make it never check for idleness, check out the Set Delay option in the Menu.

9. The AI cannot see/hear/taste/smell/feel any 'things' you refer to, so it can never have any contextual understanding of what exactly the 'thing' is (the way you understand it). This also means it'll never understand you trying to reference it (or yourself) directly, as it can never have a concept of anything external being something different from it without spatial recognition gained from sight/touch/sound.

10. In general... keep it simple. The simpler you speak to it, the better it learns.

For help, check Discord: [https://discord.gg/3yJ8rce](https://discord.gg/3yJ8rce)

For more information and details of how the AI works, check the Forum: [http://realai.freeforums.net/#category-3](http://realai.freeforums.net/#category-3)
"""

    var body: some View {
        VStack(spacing: 8) {
            ScrollView {
                Text(LocalizedStringKey(tips))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)

            Button {
                model.closeTips()
            } label: {
                Text("OK").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

// MARK: - Thoughts (Thought Log)

struct ThoughtsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 8) {
            Text("Thoughts")
                .font(.headline)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(model.thoughtLines.enumerated()), id: \.offset) { item in
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
                .onChange(of: model.thoughtLines) { _ in
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }

            Button {
                model.closeSubScreen()
            } label: {
                Text("OK").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

// MARK: - Word Fix

struct WordFixView: View {
    @EnvironmentObject var model: AppModel
    @State private var selected = 0
    @State private var newText = ""
    @State private var search = ""
    @State private var working = false

    private var visibleIndices: [Int] {
        if search.isEmpty {
            return Array(model.wordList.indices)
        }
        return model.wordList.indices.filter { model.wordList[$0].localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 8) {
            Text("Word Fix")
                .font(.headline)

            TextField("Search", text: $search)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()

            List(visibleIndices, id: \.self) { i in
                Button {
                    selected = i
                    newText = model.wordList[i]
                } label: {
                    HStack {
                        Text(model.wordList[i].isEmpty ? "(empty)" : model.wordList[i])
                            .foregroundColor(.primary)
                        Spacer()
                        if i == selected {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            .listStyle(.plain)

            TextField("New spelling", text: $newText)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()

            HStack {
                Button("Back") {
                    model.closeSubScreen()
                }
                .buttonStyle(.bordered)
                .disabled(working)

                Spacer()

                Button("Accept") {
                    working = true
                    let index = selected
                    let text = newText
                    Task {
                        await model.applyWordFix(index: index, newWord: text)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(working || newText.isEmpty)
            }

            if working {
                ProgressView()
            }
        }
        .padding()
        .onAppear {
            selected = 0
            newText = model.wordList.first ?? ""
        }
    }
}

// MARK: - Set Delay

struct DelayView: View {
    @EnvironmentObject var model: AppModel
    @State private var selection = 0
    private let options = ["10 seconds", "20 seconds", "30 seconds", "Infinite"]

    var body: some View {
        VStack(spacing: 16) {
            Text("Set Delay")
                .font(.headline)

            Text("How long the AI waits while you are idle before it tries to start a conversation.")
                .font(.footnote)
                .multilineTextAlignment(.center)

            Picker("Delay", selection: $selection) {
                ForEach(0..<options.count, id: \.self) { i in
                    Text(options[i]).tag(i)
                }
            }
            .pickerStyle(.wheel)

            HStack {
                Button("Back") {
                    model.closeSubScreen()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Accept") {
                    model.applyDelay(selection: selection)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .onAppear {
            selection = model.delaySelection
        }
    }
}

// MARK: - Response Types

struct ResponsesView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 16) {
            Text("Response Types")
                .font(.headline)

            Toggle("Topic Response Method", isOn: Binding(
                get: { model.topicBased },
                set: { model.setResponseMethod(0, $0) }))

            Toggle("Condition Response Method", isOn: Binding(
                get: { model.conditionBased },
                set: { model.setResponseMethod(1, $0) }))

            Toggle("Procedural Response Method", isOn: Binding(
                get: { model.proceduralBased },
                set: { model.setResponseMethod(2, $0) }))

            Spacer()

            Button {
                model.closeSubScreen()
            } label: {
                Text("OK").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
