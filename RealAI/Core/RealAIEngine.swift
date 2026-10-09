import Foundation

struct EngineSettings {
    var delay: String = "10 seconds"
    var advanced: Bool = false
    var topicBased: Bool = true
    var conditionBased: Bool = true
    var proceduralBased: Bool = true
    var speech: Bool = false
}

/// Port von Logic.java + Util.java (+ den Datenoperationen aus MainActivity).
///
/// Die statischen Variablen von `Logic` sind hier Eigenschaften des Actors. Jede Methode läuft
/// komplett ohne Unterbrechung, genau wie im Original, wo alles auf dem UI-Thread serialisiert war.
actor RealAIEngine {
    let store = BrainStore()

    // Logic-Zustand
    private var lastResponse = ""
    private var initiation = false
    private var newInput = false
    private var userInput = false
    private var advanced = false
    private var topicBased = true
    private var conditionBased = true
    private var proceduralBased = true
    private var speech = false
    private var delaySetting = "10 seconds"

    private var lastResponseThinking = ""
    private var topics: [String] = []
    private var topicsThinking: [String] = []

    // MARK: - Start / Einstellungen (MainActivity.createBrain)

    func load() -> EngineSettings {
        store.ensureBase()

        if !store.configExists() {
            saveConfig()
        } else {
            let d = store.configValue("Delay:")
            if d == "10 seconds" || d == "20 seconds" || d == "30 seconds" || d == "Infinite" {
                delaySetting = d
            }
            if let v = parseBool(store.configValue("Advanced:")) { advanced = v }
            if let v = parseBool(store.configValue("Topic Response Method:")) { topicBased = v }
            if let v = parseBool(store.configValue("Condition Response Method:")) { conditionBased = v }
            if let v = parseBool(store.configValue("Procedural Response Method:")) { proceduralBased = v }
            if let v = parseBool(store.configValue("Speech:")) { speech = v }
        }
        return currentSettings()
    }

    private func parseBool(_ s: String) -> Bool? {
        if s == "true" { return true }
        if s == "false" { return false }
        return nil
    }

    func currentSettings() -> EngineSettings {
        return EngineSettings(delay: delaySetting,
                              advanced: advanced,
                              topicBased: topicBased,
                              conditionBased: conditionBased,
                              proceduralBased: proceduralBased,
                              speech: speech)
    }

    private func saveConfig() {
        store.writeConfig(delay: delaySetting,
                          advanced: advanced,
                          topic: topicBased,
                          condition: conditionBased,
                          procedural: proceduralBased,
                          speech: speech)
    }

    func setAdvanced(_ value: Bool) {
        advanced = value
        saveConfig()
    }

    func setSpeech(_ value: Bool) {
        speech = value
        saveConfig()
    }

    func setDelay(_ value: String) {
        delaySetting = value
        saveConfig()
    }

    /// index: 0 = Topic, 1 = Condition, 2 = Procedural
    func setResponseMethod(index: Int, value: Bool) {
        if index == 0 {
            topicBased = value
        } else if index == 1 {
            conditionBased = value
        } else if index == 2 {
            proceduralBased = value
        }
        saveConfig()
    }

    /// Logic.Initiation = false (wird gesetzt, sobald der Nutzer tippt)
    func setInitiation(_ value: Bool) {
        initiation = value
    }

    // MARK: - Aktionen aus MainActivity

    func historyLines() -> [String] {
        return store.getHistory()
    }

    func thoughtLines() -> [String] {
        return store.getThoughts()
    }

    func allWords() -> [String] {
        return store.getWords().map { $0.word }
    }

    /// Respond-Runnable (Zweig für Nutzereingabe). Gibt nil zurück, wenn die Eingabe nicht verarbeitet wurde.
    func handleUserInput(_ rawInput: String) -> String? {
        initiation = false
        userInput = true

        guard let wordArray = prepInput(rawInput) else {
            return nil
        }

        var history = store.getHistory()
        let input = rulesCheck(rawInput)
        history.append("User: " + input)

        let output = respond(wordArray, input)
        if !output.isEmpty {
            history.append("AI: " + output)
        }

        store.saveHistory(history)
        store.clearLeftovers()
        return output
    }

    /// MainActivity.AttentionSpan: die KI versucht, selbst ein Gespräch zu beginnen.
    func attentionSpan() -> String {
        newInput = false
        initiation = true
        userInput = false

        let output = respond([], "")
        if !output.isEmpty {
            var history = store.getHistory()
            history.append("AI: " + output)
            store.saveHistory(history)
            cleanMemory()
        }
        return output
    }

    /// Thought-Runnable: ein Denkschritt.
    func thinkStep() -> Bool {
        userInput = false

        var thoughts = store.getThoughts()
        let wordArray = prepInput(lastResponseThinking)

        lastResponseThinking = think(wordArray)
        lastResponseThinking = rulesCheck(lastResponseThinking)

        if !lastResponseThinking.isEmpty {
            thoughts.append("NLP: " + lastResponseThinking)
            store.saveThoughts(thoughts)
            store.clearLeftovers()
            return true
        }
        return false
    }

    func newSession() {
        newInput = false
        var history = store.getHistory()
        history.append("---New Session---")
        store.saveHistory(history)
        cleanMemory()
    }

    func encourage() {
        cleanMemory()
        adjustLastResponse(by: 1)
        var history = store.getHistory()
        history.append("---New Session---")
        store.saveHistory(history)
        newInput = false
    }

    func discourage() {
        cleanMemory()
        adjustLastResponse(by: -1)
        var history = store.getHistory()
        history.append("---New Session---")
        store.saveHistory(history)
        newInput = false
    }

    /// Acknowledge_Erase (nach Bestätigung)
    func eraseMemory() {
        store.eraseMemory()
        lastResponse = ""
        lastResponseThinking = ""
        topics.removeAll()
    }

    // MARK: - Word Fix (MainActivity.WordFix)

    func wordFix(index: Int, newWord: String) {
        var data = store.getWords()
        if index < 0 || index >= data.count {
            return
        }
        let oldWord = data[index].word
        if oldWord.isEmpty || newWord.isEmpty {
            return
        }

        var input = store.getInputList()
        for i in 0..<input.count {
            var output = store.getAllOutputs(input[i])
            for j in 0..<output.count {
                if output[j].contains(oldWord) {
                    output[j] = output[j].replacingOccurrences(of: oldWord, with: newWord)
                }
            }
            store.saveOutput(output, input: input[i])

            if input[i].contains(oldWord) {
                let oldInput = input[i]
                let newInputName = oldInput.replacingOccurrences(of: oldWord, with: newWord)
                input[i] = newInputName
                store.renameOutputFile(from: oldInput, to: newInputName)
            }
        }
        store.saveInputList(input)

        let words = data.map { $0.word }
        for w in words {
            var pre = store.getPreWords(w)
            for j in 0..<pre.count {
                if pre[j].word == oldWord {
                    pre[j].word = newWord
                    store.renamePreFile(from: oldWord, to: newWord)
                }
            }
            store.savePreWords(pre, word: w)

            var pro = store.getProWords(w)
            for j in 0..<pro.count {
                if pro[j].word == oldWord {
                    pro[j].word = newWord
                    store.renameProFile(from: oldWord, to: newWord)
                }
            }
            store.saveProWords(pro, word: w)
        }

        data = store.getWords()
        if index < data.count {
            data[index].word = newWord
            store.saveWords(data)
        }
    }

    // MARK: - Util (Port von Util.java)

    /// Util.CleanMemory. Das Original prüfte versehentlich das falsche Verzeichnis (getFilesDir statt
    /// Brain/) und kürzte dadurch die InputList fast komplett. Hier wird die erkennbare Absicht umgesetzt:
    /// Eingaben ohne (sinnvolle) Antwortdatei werden aus der Liste entfernt.
    private func cleanMemory() {
        let input = store.getInputList()
        if input.count == 0 {
            return
        }
        var kept: [String] = []
        for memoryCheck in input {
            if store.outputFileExists(memoryCheck) {
                let output = store.getAllOutputs(memoryCheck)
                if output.count == 0 {
                    store.deleteOutputFile(memoryCheck)
                } else if output.count == 1 && output[0].contains("~") {
                    store.deleteOutputFile(memoryCheck)
                } else {
                    kept.append(memoryCheck)
                }
            }
        }
        store.saveInputList(kept)
    }

    private func adjustLastResponse(by delta: Int) {
        if lastResponse == "" {
            return
        }
        lastResponse = punctuationFix(lastResponse)
        let wordArray = J.split(lastResponse, " ")
        if wordArray.count < 2 {
            return
        }

        for pro in 0..<(wordArray.count - 1) {
            var data = store.getProWords(wordArray[pro])
            if let idx = data.firstIndex(where: { $0.word == wordArray[pro + 1] }) {
                applyDelta(&data[idx], delta)
                store.saveProWords(data, word: wordArray[pro])
            }
        }

        for pre in 1..<wordArray.count {
            var data = store.getPreWords(wordArray[pre])
            if let idx = data.firstIndex(where: { $0.word == wordArray[pre - 1] }) {
                applyDelta(&data[idx], delta)
                store.savePreWords(data, word: wordArray[pre])
            }
        }
    }

    private func applyDelta(_ d: inout WordData, _ delta: Int) {
        if delta > 0 {
            d.frequency += 1
        } else if d.frequency > 0 {
            d.frequency -= 1
        }
    }

    private func getMin(_ list: [Int]) -> Int {
        var lowest = Int.max
        for i in list {
            if i <= lowest {
                lowest = i
            }
        }
        return lowest
    }

    private func getMax(_ list: [Int]) -> Int {
        var highest = 0
        for i in list {
            if i >= highest {
                highest = i
            }
        }
        return highest
    }

    private func choose(_ list: [Int]) -> Int {
        let maxValue = getMax(list)
        var result = 0
        if list.count > 0 && maxValue > 0 {
            for i in list {
                let choice = Int.random(in: 0..<maxValue)
                if i >= choice {
                    result = i
                    break
                }
            }
        }
        return result
    }

    private func punctuationFix(_ oldWord: String) -> String {
        var word = Array(oldWord)
        let marks: [Character] = ["$", "?", ".", "!", ",", ";"]
        var i = 0
        while i < word.count {
            if i > 0 {
                if marks.contains(word[i]) && word[i - 1] != " " {
                    word.insert(" ", at: i)
                }
            } else if marks.contains(word[i]) {
                word.insert(" ", at: i)
            }
            i += 1
        }
        return String(word)
    }

    private func isTerminal(_ c: Character) -> Bool {
        return c == "." || c == "!" || c == "$" || c == "?"
    }

    private func isMultiPhrase(_ input: String) -> Bool {
        var count = 0
        for c in input {
            if isTerminal(c) {
                count += 1
            }
        }
        return count > 1
    }

    private func isMultiPhrase(words wordArray: [String]?) -> Bool {
        guard let wordArray = wordArray else {
            return false
        }
        var count = 0
        for w in wordArray {
            if w == " ." || w == " !" || w == " $" || w == " ?" {
                count += 1
            }
        }
        return count > 1
    }

    private func getLastPhrase(_ input: String) -> String? {
        let chars = Array(input)
        if chars.count > 1 {
            var startIndex = chars.count - 1
            var i = chars.count - 1
            while i > 0 {
                if isTerminal(chars[i]) && !isTerminal(chars[i - 1]) {
                    startIndex = i
                }
                i -= 1
            }

            if chars.count > 3 {
                var j = startIndex - 1
                while j > 0 {
                    if isTerminal(chars[j]) {
                        let from = j + 2
                        if from <= chars.count {
                            return String(chars[from...])
                        }
                        return ""
                    }
                    j -= 1
                }
            }
        }
        return nil
    }

    private func getFirstPhrase(_ input: String) -> String? {
        let chars = Array(input)
        if chars.count > 2 {
            for i in 0..<chars.count {
                if isTerminal(chars[i]) {
                    return String(chars[0...i])
                }
            }
        }
        return nil
    }

    private func isEndMarkerToken(_ w: String) -> Bool {
        return w == " ." || w == " $" || w == " !" || w == " ,"
    }

    /// Util.RulesCheck: Satzzeichen, Großschreibung, Schlusspunkt.
    func rulesCheck(_ input: String) -> String {
        var response = input

        if J.length(response) > 1 && response != "" {
            // "$" steht intern für "?"
            response = J.replaceWhilePastStart(response, "$", "?")

            if isMultiPhrase(response) {
                let wordArray = J.split(punctuationFix(response), " ")
                var sb = ""
                var phrases: [String] = []
                for word in wordArray {
                    if word == "." || word == "!" || word == "?" {
                        sb += word + " "
                        phrases.append(sb)
                        sb = ""
                    } else {
                        sb += word + " "
                    }
                }

                var results: [String] = []
                for phrase in phrases {
                    var newPhrase = phrase
                    if let first = phrase.first, !first.isUppercase {
                        newPhrase = String(first).uppercased() + String(phrase.dropFirst())
                    }
                    results.append(newPhrase)
                }
                response = results.joined()
            } else {
                if let first = response.first, !first.isUppercase {
                    response = String(first).uppercased() + String(response.dropFirst())
                }
            }

            response = J.replaceWhilePastStart(response, " ,", ",")
            response = J.replaceWhilePastStart(response, " ;", ";")
            response = J.replaceWhilePastStart(response, " .", ".")
            response = J.replaceWhilePastStart(response, " ?", "?")
            response = J.replaceWhilePastStart(response, " !", "!")

            if response.count > 0 {
                while let last = response.last, last == " " {
                    response.removeLast()
                }
                // (Im Original wäre ein reiner Leerzeichen-String hier eine Endlosschleife.)
                guard let lastLetter = response.last else {
                    return ""
                }
                if lastLetter != "." && lastLetter != "?" && lastLetter != "!" {
                    response += "."
                }
            }
        }

        return response
    }

    private func getTopicRelated(_ topics: [String]) -> [String] {
        var related: [String] = []
        var inputList: [String] = []

        let input = store.getInputList()
        if input.count > 0 {
            // Alles mit passenden Themen
            for a in 0..<input.count {
                var count = 0
                let list = store.getTopics(input[a])
                for result in list {
                    for t in topics {
                        if result == t {
                            count += 1
                        }
                    }
                }
                if count >= topics.count {
                    inputList.append(input[a])
                }
            }

            if inputList.count > 0 {
                // Höchste Themenhäufigkeit
                var frequencies: [Int] = []
                for result in inputList {
                    let outputTopics = store.getOutputListOnlyTopics(result)
                    for line in outputTopics {
                        let topic = J.split(line, "~")
                        if topic.count > 1, let f = Int(topic[1]) {
                            for t in topics {
                                if topic[0] == "#" + t {
                                    frequencies.append(f)
                                }
                            }
                        }
                    }
                }

                let maxFrequency = getMax(frequencies)
                if maxFrequency > 0 {
                    for result in inputList {
                        let outputTopics = store.getOutputListOnlyTopics(result)
                        for line in outputTopics {
                            let topic = J.split(line, "~")
                            guard topic.count > 1, let num = Int(topic[1]) else {
                                continue
                            }
                            var found = false
                            for t in topics {
                                if topic[0] == "#" + t && num == maxFrequency {
                                    found = true
                                    related.append(contentsOf: store.getOutputListNoRelated(result))
                                    break
                                }
                            }
                            if found {
                                break
                            }
                        }
                    }
                }
            }
        }

        return related
    }

    private func getPhraseRelated(_ phrase: String) -> [String] {
        var related: [String] = []
        let inputList = store.getInputList()
        for input in inputList {
            let list = store.getOutputListNoRelated(input)
            for output in list {
                if output == phrase {
                    let r = store.getRelatedOutputs(input, phrase: phrase)
                    if r.count > 0 {
                        related.append(contentsOf: r)
                    }
                }
            }
        }
        return related
    }

    private func getLowestFrequencies(_ wordArray: [String]?) -> [String] {
        var lowestWords: [String] = []
        var words: [String] = []
        var frequencies: [Int] = []

        let data = store.getWords()

        if let wordArray = wordArray {
            for word in wordArray {
                for d in data {
                    if d.word == word {
                        words.append(d.word)
                        frequencies.append(d.frequency)
                    }
                }
            }
        }

        if frequencies.count > 0 {
            let lowestF = getMin(frequencies)
            var randomOnes: [Int] = []
            for b in 0..<frequencies.count {
                if frequencies[b] == lowestF {
                    randomOnes.append(b)
                }
            }

            for idx in randomOnes {
                let word = words[idx].lowercased()
                let accepted = !isEndMarkerToken(word)
                if accepted && !lowestWords.contains(word) {
                    lowestWords.append(word)
                }
            }
        }

        return lowestWords
    }

    private func getRandomWord() -> String {
        let words = store.getWords().map { $0.word }
        var lowestWord = ""

        if words.count > 0 {
            for _ in 0..<words.count {
                let choice = Int.random(in: 0..<words.count)
                lowestWord = words[choice]
                let accepted = !isEndMarkerToken(lowestWord)
                if accepted {
                    lowestWord = lowestWord.lowercased()
                    break
                }
            }
        }

        return lowestWord
    }

    private func updateInputList(_ input: String) {
        var newInputText = input
        var inputList = store.getInputList()

        if J.length(input) > 1 {
            newInputText = punctuationFix(newInputText)
        }

        if !inputList.contains(newInputText) {
            inputList.append(newInputText)
            store.saveInputList(inputList)
        }
    }

    private func currentLastResponseForOutput() -> String? {
        if isMultiPhrase(lastResponse) {
            return getLastPhrase(lastResponse)
        }
        return lastResponse
    }

    private func updateOutputList(_ input: String) {
        var tempInput = input

        if var tempLast = currentLastResponseForOutput() {
            if J.length(tempInput) > 1 {
                tempInput = punctuationFix(tempInput)
            }
            if J.length(tempLast) > 1 {
                tempLast = punctuationFix(tempLast)
            }

            // Neue Eingabe zur Antwortliste der letzten Antwort hinzufügen
            var output = store.getAllOutputs(tempLast)
            if !output.contains(tempInput) && tempLast != tempInput {
                output.append(tempInput)
                store.saveOutput(output, input: tempLast)
            }
        }
    }

    private func updateOutputListMultiPhrase(_ inputs: [String]) {
        if inputs.isEmpty {
            return
        }

        var tempInput = inputs.joined(separator: "^")
        var tempInputFirst = inputs[0]

        if var tempLast = currentLastResponseForOutput() {
            if J.length(tempInput) > 1 {
                tempInput = punctuationFix(tempInput)
            }
            if J.length(tempInputFirst) > 1 {
                tempInputFirst = punctuationFix(tempInputFirst)
            }
            if J.length(tempLast) > 1 {
                tempLast = punctuationFix(tempLast)
            }

            var output = store.getAllOutputs(tempLast)

            if !output.contains(tempInputFirst) && tempLast != tempInputFirst {
                output.append(tempInput)
                store.saveOutput(output, input: tempLast)
            } else if tempLast != tempInputFirst {
                var relatedOutputs = store.getRelatedOutputs(tempLast, phrase: tempInputFirst)

                for i in 0..<inputs.count {
                    let fixed = punctuationFix(inputs[i])
                    if !relatedOutputs.contains(fixed) {
                        relatedOutputs.append(fixed)
                    }
                }

                var sb = tempInputFirst
                for related in relatedOutputs {
                    if related != tempInputFirst {
                        sb += "^" + related
                    }
                }

                for i in 0..<output.count {
                    if output[i].contains(tempInputFirst) {
                        output[i] = sb
                        break
                    }
                }

                store.saveOutput(output, input: tempLast)
            }
        }
    }

    private func genTopics(_ wordArray: [String], _ oldTopics: [String]) -> [String] {
        let lowestWords = getLowestFrequencies(wordArray)

        // Neue Themen, aber bestehende behalten, wenn sie in der Eingabe vorkommen
        var newTopics = lowestWords
        for topic in oldTopics {
            for word in wordArray {
                if word == topic {
                    newTopics.append(topic)
                    break
                }
            }
        }
        return newTopics
    }

    private func genTopicsForThinking(_ wordArray: [String]?) {
        guard let wordArray = wordArray else {
            return
        }
        let lowestWords = getLowestFrequencies(wordArray)
        let oldTopics = topicsThinking

        topicsThinking = lowestWords
        for topic in oldTopics {
            for word in wordArray {
                if word == topic {
                    topicsThinking.append(topic)
                    break
                }
            }
        }
    }

    private func addTopics(_ input: String, _ topics: [String]) {
        var tempInput = input
        if J.length(tempInput) > 1 {
            tempInput = punctuationFix(tempInput)
        }

        // Themen der aktuellen Eingabe in deren Antwortdatei pflegen
        var output = store.getAllOutputs(tempInput)

        if output.count > 0 {
            var i = 0
            while i < output.count {
                if output[i].contains("#") {
                    let topic = J.split(output[i], "~")

                    var match = false
                    for word in topics {
                        if topic.count > 0 && topic[0] == "#" + word.lowercased() {
                            match = true
                        }
                    }

                    // (Im Original wird die Zahl bei einem Treffer nur lokal erhöht und nie gespeichert.)
                    if !match {
                        if topic.count > 1, let num = Int(topic[1]) {
                            if num - 1 > 0 {
                                output[i] = topic[0] + "~" + String(num - 1)
                            } else {
                                output.remove(at: i)
                                i -= 1
                            }
                        }
                    }
                } else if output[i].contains("~") {
                    output.remove(at: i)
                    i -= 1
                }
                i += 1
            }

            store.saveOutput(output, input: tempInput)
        }

        // Fehlende aktuelle Themen hinzufügen
        output = store.getAllOutputs(tempInput)
        for word in topics {
            var found = false

            for line in output {
                if line.contains("#") {
                    let topic = J.split(line, "~")
                    if topic.count > 0 && topic[0] == "#" + word.lowercased() {
                        found = true
                        break
                    }
                }
            }

            if !found {
                if !(isEndMarkerToken(word) || word == "") {
                    output.insert("#" + word + "~7", at: 0)
                }
            }
        }
        store.saveOutput(output, input: tempInput)
    }

    // MARK: - Logic (Port von Logic.java)

    private func createWordArray(_ input: String) -> [String]? {
        let reserved: [String] = ["|", "\\", "*", "<", "\"", ":", ">", "#"]
        var docChars: [String] = input.map { String($0) }

        var i = 0
        while i < docChars.count {
            var okay = true
            if reserved.contains(docChars[i]) {
                okay = false
                docChars.remove(at: i)
                i -= 1
            }

            if okay {
                let c = docChars[i]
                if c == "," {
                    docChars[i] = " ,"
                } else if c == ";" {
                    docChars[i] = " ;"
                } else if c == "?" {
                    docChars[i] = " $"
                } else if c == "$" {
                    docChars[i] = " $"
                } else if c == "!" {
                    docChars[i] = " !"
                } else if c == "." {
                    if docChars.count >= i + 2 {
                        if docChars[i + 1] == "." {
                            docChars[i] = " ."
                            i = i + 2
                        } else {
                            docChars[i] = " ."
                        }
                    } else {
                        docChars[i] = " ."
                    }
                }
            }
            i += 1
        }

        let result = J.trim(docChars.joined())
        if !result.isEmpty {
            var wordArray = J.split(result, " ")
            for k in 0..<wordArray.count {
                wordArray[k] = punctuationFix(wordArray[k])
            }
            return wordArray
        }

        return nil
    }

    private func handleMultiPhrase(_ wordArray: [String]?) -> [String]? {
        guard let wordArray = wordArray, isMultiPhrase(words: wordArray) else {
            return nil
        }

        var sb = ""
        var phrases: [String] = []
        for word in wordArray {
            if word == " ." || word == " !" || word == " $" {
                sb += word
                phrases.append(sb)
                sb = ""
            } else {
                sb += word + " "
            }
        }

        var results: [String] = []
        for phrase in phrases {
            results.append(rulesCheck(phrase))
        }
        return results
    }

    private func learn(_ wordArray: [String]) {
        updateExistingFrequencies(wordArray)
        addNewWords(wordArray)
        updatePreWords(wordArray)
        updateProWords(wordArray)
    }

    func prepInput(_ input: String) -> [String]? {
        var wordArray = createWordArray(input)
        let inputs = handleMultiPhrase(wordArray)

        if let inputs = inputs {
            if userInput || advanced {
                for phrase in inputs {
                    wordArray = createWordArray(phrase)
                    updateInputList(phrase)
                    if let wa = wordArray {
                        learn(wa)
                    }
                }

                if newInput {
                    updateOutputListMultiPhrase(inputs)
                }
            } else if inputs.count > 0 {
                let last = inputs[inputs.count - 1]
                wordArray = createWordArray(last)
            }
        } else if let wa = wordArray, (userInput || advanced) {
            updateInputList(input)
            learn(wa)

            if newInput {
                updateOutputList(input)
            }
        }

        return wordArray
    }

    private func updateExistingFrequencies(_ wordArray: [String]) {
        var data = store.getWords()

        for a in 0..<data.count {
            for word in wordArray {
                if data[a].word == word {
                    data[a].frequency += 1
                }
            }
        }

        store.saveWords(data)
    }

    private func addNewWords(_ wordArray: [String]) {
        if wordArray.count > 0 {
            var data = store.getWords()

            for word in wordArray {
                var found = false
                if word != "" {
                    for d in data {
                        if d.word == word {
                            found = true
                            break
                        }
                    }
                }

                if !found {
                    data.append(WordData(word: word, frequency: 1))
                }
            }

            store.saveWords(data)
        }
    }

    private func updatePreWords(_ wordArray: [String]) {
        if wordArray.count < 2 {
            return
        }
        for i in 0..<(wordArray.count - 1) {
            // Aktuelle Pre-Wörter holen
            var data = store.getPreWords(wordArray[i + 1])

            if let index = data.firstIndex(where: { $0.word == wordArray[i] }) {
                // Häufigkeit eines bekannten Wortes erhöhen
                data[index].frequency += 1
                store.savePreWords(data, word: wordArray[i + 1])
            } else if wordArray[i] != "" {
                // Oder Wort hinzufügen
                data.append(WordData(word: wordArray[i], frequency: 1))
                store.savePreWords(data, word: wordArray[i + 1])
            }
        }
    }

    private func updateProWords(_ wordArray: [String]) {
        if wordArray.count < 2 {
            return
        }
        for i in 0..<(wordArray.count - 1) {
            var data = store.getProWords(wordArray[i])

            if let index = data.firstIndex(where: { $0.word == wordArray[i + 1] }) {
                data[index].frequency += 1
                store.saveProWords(data, word: wordArray[i])
            } else if wordArray[i + 1] != "" {
                data.append(WordData(word: wordArray[i + 1], frequency: 1))
                store.saveProWords(data, word: wordArray[i])
            }
        }
    }

    private func randomElement(_ list: [String]) -> String {
        return list[Int.random(in: 0..<list.count)]
    }

    func respond(_ wordArray: [String], _ input: String) -> String {
        var output = ""
        var response = ""

        if userInput {
            topics = genTopics(wordArray, topics)
            addTopics(input, topics)
            lastResponseThinking = input
        } else if initiation && topics.count == 0 {
            topics.append(getRandomWord())
        }

        if topics.count > 0 {
            var matchFound = false

            if advanced {
                let choice = Int.random(in: 0..<topics.count)
                let chosenTopic = topics[choice]
                response += generateResponse(chosenTopic)

                // Wenn mit dem Thema nichts Neues erzeugt wurde, Thema wechseln
                if initiation && response == chosenTopic {
                    topics.removeAll()
                }
            } else {
                // Vorhandene Antworten über die Themen suchen
                if topicBased {
                    let info = getTopicRelated(topics)
                    if info.count > 0 {
                        response += randomElement(info)
                        matchFound = true

                        if initiation && rulesCheck(response) == getFirstPhrase(lastResponse) {
                            topics.removeAll()
                            matchFound = false
                        }
                    }
                }

                // Sonst bedingte Antworten
                if !matchFound && conditionBased {
                    let tempInput = punctuationFix(input)
                    let outputList = store.getOutputListNoRelated(tempInput)
                    if outputList.count > 0 {
                        response += randomElement(outputList)
                        matchFound = true

                        if initiation && rulesCheck(response) == getFirstPhrase(lastResponse) {
                            topics.removeAll()
                            matchFound = false
                        }
                    }
                }

                // Sonst prozedural mit dem Thema erzeugen
                if !matchFound && proceduralBased {
                    if topics.count > 0 {
                        response += generateResponse(randomElement(topics))
                    } else {
                        response += generateResponse(getRandomWord())
                    }

                    if initiation && rulesCheck(response) == getFirstPhrase(lastResponse) {
                        topics.removeAll()
                    }
                }
            }

            let currentResponse = response
            let relatedPhrases = getPhraseRelated(currentResponse)
            if relatedPhrases.count > 0 {
                for related in relatedPhrases {
                    if related != currentResponse {
                        response += " " + related
                    }
                }
            }

            let responseOutput = rulesCheck(response)

            if !responseOutput.isEmpty {
                output = responseOutput
                lastResponse = responseOutput
                newInput = true
            } else {
                output = ""
            }
        } else {
            output = ""
        }

        return output
    }

    func think(_ wordArray: [String]?) -> String {
        var response = ""

        genTopicsForThinking(wordArray)

        if topicsThinking.count > 0 {
            var matchFound = false

            let info = getTopicRelated(topicsThinking)
            if info.count > 0 {
                response += randomElement(info)
                matchFound = true
            }

            if !matchFound {
                let tempInput = punctuationFix(lastResponseThinking)
                let outputList = store.getOutputListNoRelated(tempInput)
                if outputList.count > 0 {
                    response += randomElement(outputList)
                    matchFound = true
                }
            }

            if !matchFound {
                response += generateResponse(randomElement(topicsThinking))

                if rulesCheck(response) == lastResponseThinking {
                    response += generateResponse(getRandomWord())
                }
            }

            let currentResponse = response
            let relatedPhrases = getPhraseRelated(currentResponse)
            if relatedPhrases.count > 0 {
                for related in relatedPhrases {
                    if related != currentResponse {
                        response += " " + related
                    }
                }
            }
        } else {
            response += generateResponse(getRandomWord())
        }

        let responseOutput = rulesCheck(response)
        return responseOutput.isEmpty ? "" : responseOutput
    }

    /// Wählt aus (Wort, Häufigkeit) zufällig ein Wort, gewichtet über `choose`.
    private func pickWord(from data: [WordData]) -> String? {
        var words: [String] = []
        var frequencies: [Int] = []

        for d in data {
            if d.frequency > 0 {
                words.append(d.word)
                frequencies.append(d.frequency)
            }
        }

        if frequencies.count == 0 {
            return nil
        }

        let highest = choose(frequencies)
        var randomOnes: [Int] = []
        for b in 0..<frequencies.count {
            if frequencies[b] == highest {
                randomOnes.append(b)
            }
        }
        if randomOnes.isEmpty {
            return nil
        }
        let choice = Int.random(in: 0..<randomOnes.count)
        return words[randomOnes[choice]]
    }

    private func generateResponse(_ lowestWord: String) -> String {
        var currentPre = lowestWord
        var currentPro = lowestWord
        var response = currentPre
        var wordsFound = true
        var repeaterCheck = ""

        // Rückwärts: vorangehende Wörter anfügen
        while wordsFound {
            let data = store.getPreWords(currentPre)
            if data.count > 0 {
                if let picked = pickWord(from: data) {
                    currentPre = picked

                    if J.length(currentPre) > 1 {
                        if let firstLetter = currentPre.first, firstLetter.isUppercase {
                            response = currentPre + " " + response
                            break
                        }
                    }

                    let checker = J.split(response, " ")
                    for item in checker {
                        let check = punctuationFix(item)
                        if check == currentPre {
                            wordsFound = false
                            break
                        }
                    }

                    if wordsFound {
                        response = currentPre + " " + response
                    }
                } else {
                    wordsFound = false
                }
            } else {
                wordsFound = false
            }
        }

        wordsFound = true

        // Vorwärts: nachfolgende Wörter anfügen
        while wordsFound {
            let data = store.getProWords(currentPro)
            if data.count > 0 {
                if let picked = pickWord(from: data) {
                    currentPro = picked

                    if repeaterCheck.count > 0 {
                        let checker = J.split(repeaterCheck, " ")
                        for item in checker {
                            let check = punctuationFix(item)
                            if check == currentPro {
                                wordsFound = false
                                break
                            }
                        }
                    }

                    if wordsFound {
                        response = response + " " + currentPro
                        repeaterCheck = repeaterCheck + currentPro + " "

                        if currentPro == "." || currentPro == "$" || currentPro == "!" {
                            break
                        }
                    }
                } else {
                    wordsFound = false
                }
            } else {
                wordsFound = false
            }
        }

        return response
    }
}
