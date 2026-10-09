import Foundation

/// Port von WordData.java
struct WordData {
    var word: String
    var frequency: Int
}

/// Port von Data.java.
///
/// Das Dateiformat entspricht der Android-App (Ordner `Brain/` mit `Config.ini`, `Words.txt`,
/// `InputList.txt`, `Pre-<wort>.txt`, `Pro-<wort>.txt`, `<eingabe>.txt`, `History/`, `Thoughts/`).
///
/// Einzige bewusste Abweichung: Dateinamen werden "case-sicher" kodiert (siehe `fileSafe`),
/// weil das iOS-Dateisystem standardmäßig NICHT zwischen Groß- und Kleinschreibung unterscheidet,
/// die KI aber "Hello" und "hello" als verschiedene Wörter behandelt.
final class BrainStore {
    let brainDir: URL
    let historyDir: URL
    let thoughtsDir: URL
    private let fm = FileManager.default

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        brainDir = docs.appendingPathComponent("Brain", isDirectory: true)
        historyDir = brainDir.appendingPathComponent("History", isDirectory: true)
        thoughtsDir = brainDir.appendingPathComponent("Thoughts", isDirectory: true)
    }

    // MARK: - Dateinamen

    /// Großbuchstaben werden zu "^" + Kleinbuchstabe, "/" "%" "^" werden prozent-kodiert.
    static func fileSafe(_ name: String) -> String {
        var out = ""
        for ch in name {
            switch ch {
            case "/":
                out += "%2F"
            case "%":
                out += "%25"
            case "^":
                out += "%5E"
            default:
                if ch.isUppercase {
                    out += "^" + String(ch).lowercased()
                } else {
                    out.append(ch)
                }
            }
        }
        return out
    }

    private var configURL: URL { brainDir.appendingPathComponent("Config.ini") }
    private var wordsURL: URL { brainDir.appendingPathComponent("Words.txt") }
    private var inputListURL: URL { brainDir.appendingPathComponent("InputList.txt") }

    private func outputURL(_ input: String) -> URL {
        return brainDir.appendingPathComponent(BrainStore.fileSafe(input) + ".txt")
    }

    private func preURL(_ word: String) -> URL {
        return brainDir.appendingPathComponent("Pre-" + BrainStore.fileSafe(word) + ".txt")
    }

    private func proURL(_ word: String) -> URL {
        return brainDir.appendingPathComponent("Pro-" + BrainStore.fileSafe(word) + ".txt")
    }

    private func dateName() -> String {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        f.locale = Locale.current
        return f.string(from: Date()).replacingOccurrences(of: "/", with: "-")
    }

    private func historyURL() -> URL {
        return historyDir.appendingPathComponent(dateName() + ".txt")
    }

    private func thoughtsURL() -> URL {
        return thoughtsDir.appendingPathComponent(dateName() + ".txt")
    }

    // MARK: - Low-Level I/O

    private func readLines(_ url: URL) -> [String]? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        let text = String(decoding: data, as: UTF8.self)
        var lines = text.components(separatedBy: .newlines)
        if let last = lines.last, last.isEmpty {
            lines.removeLast()
        }
        return lines
    }

    private func writeText(_ text: String, to url: URL) {
        let dir = url.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeLines(_ lines: [String], to url: URL) {
        var text = ""
        for line in lines {
            text += line
            text += "\n"
        }
        writeText(text, to: url)
    }

    // MARK: - Aufbau (MainActivity.createBrain)

    func ensureBase() {
        for dir in [brainDir, historyDir, thoughtsDir] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        for url in [wordsURL, inputListURL] {
            if !fm.fileExists(atPath: url.path) {
                fm.createFile(atPath: url.path, contents: Data())
            }
        }
    }

    /// Util.EraseMemory: löscht alles außer Dateien mit "Config" im Namen.
    func eraseMemory() {
        if let items = try? fm.contentsOfDirectory(atPath: brainDir.path) {
            for name in items {
                if !name.contains("Config") {
                    try? fm.removeItem(at: brainDir.appendingPathComponent(name))
                }
            }
        }
        ensureBase()
    }

    /// Util.ClearLeftovers (im Original auf das falsche Verzeichnis gerichtet, hier auf Brain/).
    func clearLeftovers() {
        for name in [".txt", ",.txt", "..txt"] {
            let url = brainDir.appendingPathComponent(name)
            if fm.fileExists(atPath: url.path) {
                try? fm.removeItem(at: url)
            }
        }
    }

    // MARK: - Config

    func configExists() -> Bool {
        return fm.fileExists(atPath: configURL.path)
    }

    func writeConfig(delay: String, advanced: Bool, topic: Bool, condition: Bool, procedural: Bool, speech: Bool) {
        var text = ""
        text += "Delay:\(delay)\n"
        text += "Advanced:\(advanced)\n"
        text += "Topic Response Method:\(topic)\n"
        text += "Condition Response Method:\(condition)\n"
        text += "Procedural Response Method:\(procedural)\n"
        text += "Speech:\(speech)\n"
        writeText(text, to: configURL)
    }

    func configValue(_ key: String) -> String {
        guard let lines = readLines(configURL) else {
            return ""
        }
        for line in lines {
            if line.contains(key) {
                let parts = J.split(line, ":")
                return parts.count > 1 ? parts[1] : ""
            }
        }
        return ""
    }

    // MARK: - Words / PreWords / ProWords

    private func parseWordLines(_ lines: [String]) -> [WordData] {
        var result: [WordData] = []
        for line in lines {
            if line.contains("~") {
                let set = J.split(line, "~")
                if set.count > 1, set[1] != "", let f = Int(set[1]) {
                    result.append(WordData(word: set[0], frequency: f))
                }
            }
        }
        return result
    }

    private func wordLines(_ data: [WordData]) -> [String] {
        return data.map { "\($0.word)~\($0.frequency)" }
    }

    func getWords() -> [WordData] {
        guard let lines = readLines(wordsURL) else {
            return []
        }
        return parseWordLines(lines)
    }

    func saveWords(_ data: [WordData]) {
        writeLines(wordLines(data), to: wordsURL)
    }

    func getPreWords(_ word: String) -> [WordData] {
        guard let lines = readLines(preURL(word)) else {
            return []
        }
        return parseWordLines(lines)
    }

    func savePreWords(_ data: [WordData], word: String) {
        writeLines(wordLines(data), to: preURL(word))
    }

    func getProWords(_ word: String) -> [WordData] {
        guard let lines = readLines(proURL(word)) else {
            return []
        }
        return parseWordLines(lines)
    }

    func saveProWords(_ data: [WordData], word: String) {
        writeLines(wordLines(data), to: proURL(word))
    }

    func renamePreFile(from oldWord: String, to newWord: String) {
        try? fm.moveItem(at: preURL(oldWord), to: preURL(newWord))
    }

    func renameProFile(from oldWord: String, to newWord: String) {
        try? fm.moveItem(at: proURL(oldWord), to: proURL(newWord))
    }

    // MARK: - Input / Output

    func getInputList() -> [String] {
        guard let lines = readLines(inputListURL) else {
            return []
        }
        return lines.filter { $0 != "" }
    }

    func saveInputList(_ input: [String]) {
        writeLines(input, to: inputListURL)
    }

    func saveOutput(_ output: [String], input: String) {
        writeLines(output, to: outputURL(input))
    }

    func outputFileExists(_ input: String) -> Bool {
        return fm.fileExists(atPath: outputURL(input).path)
    }

    func deleteOutputFile(_ input: String) {
        try? fm.removeItem(at: outputURL(input))
    }

    func renameOutputFile(from oldInput: String, to newInput: String) {
        try? fm.moveItem(at: outputURL(oldInput), to: outputURL(newInput))
    }

    func getAllOutputs(_ input: String) -> [String] {
        guard let lines = readLines(outputURL(input)) else {
            return []
        }
        return lines.filter { $0 != "" }
    }

    /// Ausgaben ohne Themen-Zeilen ("#...") und ohne Anhang nach "^".
    func getOutputListNoRelated(_ input: String) -> [String] {
        var output: [String] = []
        guard let lines = readLines(outputURL(input)) else {
            return output
        }
        for line in lines {
            if line != "" && !line.contains("#") {
                if let idx = line.firstIndex(of: "^") {
                    output.append(String(line[line.startIndex..<idx]))
                } else {
                    output.append(line)
                }
            }
        }
        return output
    }

    /// Nur Themen-Zeilen ("#wort~zahl").
    func getOutputListOnlyTopics(_ input: String) -> [String] {
        var output: [String] = []
        guard let lines = readLines(outputURL(input)) else {
            return output
        }
        for line in lines {
            if line.contains("#") {
                output.append(line)
            }
        }
        return output
    }

    func getRelatedOutputs(_ input: String, phrase: String) -> [String] {
        var output: [String] = []
        guard let lines = readLines(outputURL(input)) else {
            return output
        }
        for line in lines {
            if line != "" && line.contains(phrase) && line.contains("^") {
                output.append(contentsOf: J.split(line, "^"))
            }
        }
        return output
    }

    func getTopics(_ input: String) -> [String] {
        var result: [String] = []
        guard let lines = readLines(outputURL(input)) else {
            return result
        }
        for line in lines {
            if line.contains("#") {
                let chars = Array(line)
                if let idx = chars.firstIndex(of: "~"), idx > 1 {
                    result.append(String(chars[1..<idx]))
                }
            }
        }
        return result
    }

    // MARK: - History / Thoughts (jeweils die letzten 40 Zeilen des heutigen Tages)

    private func lastLines(of url: URL) -> [String] {
        guard let lines = readLines(url) else {
            return []
        }
        let nonEmpty = lines.filter { $0 != "" }
        return Array(nonEmpty.suffix(40))
    }

    func getHistory() -> [String] {
        return lastLines(of: historyURL())
    }

    func saveHistory(_ history: [String]) {
        writeLines(history, to: historyURL())
    }

    func getThoughts() -> [String] {
        return lastLines(of: thoughtsURL())
    }

    func saveThoughts(_ thoughts: [String]) {
        writeLines(thoughts, to: thoughtsURL())
    }
}
