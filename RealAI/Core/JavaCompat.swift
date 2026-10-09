import Foundation

/// Hilfsfunktionen, die das Verhalten der Java-Standardbibliothek nachbilden,
/// auf die sich der Original-Code verlässt (String.split, String.trim, indexOf-Schleifen).
enum J {

    /// Java `String.split(sep)` für ein wörtliches Trennzeichen:
    /// führende/mittlere leere Teile bleiben erhalten, abschließende leere Teile werden entfernt.
    static func split(_ s: String, _ sep: String) -> [String] {
        let parts = s.components(separatedBy: sep)
        if parts.count == 1 {
            return parts
        }
        var result = parts
        while let last = result.last, last.isEmpty {
            result.removeLast()
        }
        return result
    }

    /// Java `String.trim()`: entfernt alle Zeichen <= U+0020 an beiden Enden.
    static func trim(_ s: String) -> String {
        let scalars = Array(s.unicodeScalars)
        var start = 0
        var end = scalars.count
        while start < end && scalars[start].value <= 0x20 {
            start += 1
        }
        while end > start && scalars[end - 1].value <= 0x20 {
            end -= 1
        }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars[start..<end])
        return String(view)
    }

    /// Java `String.length()` (UTF-16 Einheiten).
    static func length(_ s: String) -> Int {
        return s.utf16.count
    }

    /// Entspricht der Java-Schleife
    /// `while (sb.indexOf(pattern) > 0) sb.replace(idx, idx + pattern.length(), replacement);`
    /// Es wird immer das erste Vorkommen ersetzt, und nur solange es NICHT ganz am Anfang steht.
    static func replaceWhilePastStart(_ s: String, _ pattern: String, _ replacement: String) -> String {
        var text = s
        while let r = text.range(of: pattern, options: .literal), r.lowerBound > text.startIndex {
            text.replaceSubrange(r, with: replacement)
        }
        return text
    }
}
