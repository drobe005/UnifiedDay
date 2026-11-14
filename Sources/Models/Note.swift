import Foundation
import SwiftData

/// A note kept by UnifiedDay, not by Apple's apps. Stored with SwiftData and synced
/// through the user's private iCloud. CloudKit needs a default value on every
/// property and optional relationships.
@Model
final class Note {
    var title = ""
    /// Plain text, kept for search and previews even when the note has formatting.
    var text = ""
    /// Formatting runs from `RichText`. Nil until the note is edited with formatting.
    var richText: Data?
    var createdAt = Date.now
    var updatedAt = Date.now
    var isPinned = false
    var folder: NoteFolder?
    @Relationship(deleteRule: .cascade, inverse: \NoteLink.note)
    var links: [NoteLink]? = []
    @Relationship(deleteRule: .cascade, inverse: \NoteImage.note)
    var images: [NoteImage]? = []

    init(title: String = "", text: String = "") {
        self.title = title
        self.text = text
    }

    /// The title, or the first line of text when there is no title.
    var displayTitle: String {
        if !title.isEmpty { return title }
        return text.split(whereSeparator: \.isNewline).first.map(String.init) ?? "New note"
    }

    /// Text shown under the title in lists.
    var preview: String {
        guard title.isEmpty else { return text }
        return text.split(whereSeparator: \.isNewline).dropFirst().joined(separator: " ")
    }

    /// Images in the order they were added.
    var sortedImages: [NoteImage] {
        (images ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    var attachedLinks: [NoteLink] {
        (links ?? []).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func attach(_ items: [TimelineItem], in context: ModelContext) {
        for item in items where !isAttached(to: item) {
            let link = NoteLink(item: item)
            context.insert(link)
            link.note = self
        }
        updatedAt = .now
    }

    func matches(_ query: String) -> Bool {
        title.localizedCaseInsensitiveContains(query) || text.localizedCaseInsensitiveContains(query)
    }

    func isAttached(to item: TimelineItem) -> Bool {
        (links ?? []).contains { $0.matches(item) }
    }

    /// Title and text, for sharing outside the app.
    var shareText: String {
        [title, text].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
}

/// A photo or pasted image in a note. Kept outside the main store, and synced
/// through iCloud as a file.
@Model
final class NoteImage {
    @Attribute(.externalStorage) var data: Data?
    var createdAt = Date.now
    var note: Note?

    init(data: Data) {
        self.data = data
    }

    /// Images this wide or tall are shrunk before saving, to keep iCloud use down.
    private static let maxDimension: CGFloat = 2048

    /// The image as a JPEG no larger than `maxDimension`. Nil if it isn't an image.
    static func preparedData(from data: Data) -> Data? {
        Platform.jpegData(from: data, maxDimension: maxDimension)
    }
}

/// A folder of notes. Deleting a folder keeps its notes, unfiled.
@Model
final class NoteFolder {
    /// Stable across devices, so a chosen folder can be remembered in settings.
    var uuid = UUID()
    var name = ""
    var createdAt = Date.now
    @Relationship(deleteRule: .nullify, inverse: \Note.folder)
    var notes: [Note]? = []

    init(name: String) {
        self.name = name
    }
}

/// Ties a note to an event or reminder. All occurrences of a repeating event share
/// an external identifier, so a note on one shows on the whole series.
@Model
final class NoteLink {
    var kindValue = TimelineItemKind.event.rawValue
    /// calendarItemExternalIdentifier: the same on every device.
    var externalID = ""
    /// eventIdentifier or calendarItemIdentifier: a fallback for this device.
    var localID = ""
    /// Last known title, shown when the item can't be found.
    var title = ""
    var note: Note?

    init(item: TimelineItem) {
        kindValue = item.kind.rawValue
        externalID = item.externalIdentifier
        localID = item.storeIdentifier
        title = item.title
    }

    var kind: TimelineItemKind {
        TimelineItemKind(rawValue: kindValue) ?? .event
    }

    func matches(_ item: TimelineItem) -> Bool {
        guard kind == item.kind else { return false }
        return (!externalID.isEmpty && externalID == item.externalIdentifier) || localID == item.storeIdentifier
    }
}

enum NoteStorage {
    /// Opens saved notes. Uses memory only if the store can't open, so a storage
    /// problem shows a message instead of stopping the app from launching.
    static func makeContainer() -> (container: ModelContainer, error: String?) {
        let schema = Schema([Note.self, NoteLink.self, NoteFolder.self, NoteImage.self])
        do {
            #if os(macOS)
            // The Mac reads the same iCloud notes as the TestFlight iPhone app (production),
            // so it keeps them in their own file, apart from the test notes earlier Mac
            // builds synced with iCloud's development space.
            let configuration = ModelConfiguration(
                schema: schema,
                url: URL.applicationSupportDirectory.appending(path: "Notes-Production.store"),
                cloudKitDatabase: .automatic
            )
            #else
            let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
            #endif
            return (try ModelContainer(for: schema, configurations: configuration), nil)
        } catch {
            let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            guard let container = try? ModelContainer(for: schema, configurations: memory) else {
                fatalError("Couldn't open note storage: \(error)")
            }
            return (container, "Your notes couldn't be opened. New notes won't be saved.")
        }
    }
}

extension ModelContext {
    /// Saves now and reports any failure through the service's error banner.
    @MainActor
    func saveNotes(reportingTo eventKit: EventKitService) {
        do {
            try save()
        } catch {
            eventKit.lastError = error.localizedDescription
        }
    }
}
