import SwiftUI

/// Formatting a note can use. Stored as simple runs so it round-trips through
/// iCloud exactly, since SwiftUI fonts can't be saved directly.
struct RichTextStyle: Equatable {
    var bold = false
    var italic = false
    var underline = false
    var strikethrough = false
    var heading = false

    private typealias Font = AttributeScopes.SwiftUIAttributes.FontAttribute
    private typealias Underline = AttributeScopes.SwiftUIAttributes.UnderlineStyleAttribute
    private typealias Strikethrough = AttributeScopes.SwiftUIAttributes.StrikethroughStyleAttribute

    init(bold: Bool = false, italic: Bool = false, underline: Bool = false, strikethrough: Bool = false, heading: Bool = false) {
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.strikethrough = strikethrough
        self.heading = heading
    }

    /// Reads the style back from attributes. Fonts this app didn't set count as plain.
    init(_ container: AttributeContainer) {
        let font = container[Font.self]
        for heading in [false, true] {
            for bold in [false, true] {
                for italic in [false, true] where Self.font(bold: bold, italic: italic, heading: heading) == font {
                    self.bold = bold
                    self.italic = italic
                    self.heading = heading
                }
            }
        }
        underline = container[Underline.self] != nil
        strikethrough = container[Strikethrough.self] != nil
    }

    var attributes: AttributeContainer {
        var container = AttributeContainer()
        container[Font.self] = Self.font(bold: bold, italic: italic, heading: heading)
        container[Underline.self] = underline ? .single : nil
        container[Strikethrough.self] = strikethrough ? .single : nil
        return container
    }

    func apply(to container: inout AttributeContainer) {
        container[Font.self] = Self.font(bold: bold, italic: italic, heading: heading)
        container[Underline.self] = underline ? .single : nil
        container[Strikethrough.self] = strikethrough ? .single : nil
    }

    private static func font(bold: Bool, italic: Bool, heading: Bool) -> SwiftUI.Font {
        var font: SwiftUI.Font = heading ? .title3.bold() : .body
        if bold && !heading { font = font.bold() }
        if italic { font = font.italic() }
        return font
    }
}

enum RichText {
    private struct Run: Codable {
        var text: String
        var bold: Bool?
        var italic: Bool?
        var underline: Bool?
        var strikethrough: Bool?
        var heading: Bool?
    }

    static func encode(_ text: AttributedString) -> Data? {
        let runs = text.runs.map { run in
            let style = RichTextStyle(run.attributes)
            return Run(
                text: String(text[run.range].characters),
                bold: style.bold ? true : nil,
                italic: style.italic ? true : nil,
                underline: style.underline ? true : nil,
                strikethrough: style.strikethrough ? true : nil,
                heading: style.heading ? true : nil
            )
        }
        return try? JSONEncoder().encode(runs)
    }

    /// Saved formatting, or the plain text when the note has none yet.
    static func decode(_ data: Data?, plainText: String) -> AttributedString {
        guard let data, let runs = try? JSONDecoder().decode([Run].self, from: data) else {
            return AttributedString(plainText, attributes: RichTextStyle().attributes)
        }
        var result = AttributedString()
        for run in runs {
            let style = RichTextStyle(
                bold: run.bold ?? false,
                italic: run.italic ?? false,
                underline: run.underline ?? false,
                strikethrough: run.strikethrough ?? false,
                heading: run.heading ?? false
            )
            result += AttributedString(run.text, attributes: style.attributes)
        }
        return result
    }
}
