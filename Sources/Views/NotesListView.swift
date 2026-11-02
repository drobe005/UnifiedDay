import SwiftData
import SwiftUI

/// Every note kept in UnifiedDay, newest first. Works without Calendar access,
/// since notes don't live in Apple's apps.
struct NotesListView: View {
    @Environment(EventKitService.self) private var eventKit
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @State private var searchText = ""

    private var filtered: [Note] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? notes : notes.filter { $0.matches(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { note in
                    NavigationLink {
                        NoteEditorView(note: note)
                    } label: {
                        NoteRow(note: note)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            modelContext.delete(note)
                            modelContext.saveNotes(reportingTo: eventKit)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .contentMargins(.bottom, ComposerButtonClearance.height, for: .scrollContent)
            .overlay {
                if notes.isEmpty {
                    ContentUnavailableView(
                        "No notes yet",
                        systemImage: "note.text",
                        description: Text("Tap + to write one.")
                    )
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .navigationTitle("Notes")
            .searchable(text: $searchText, prompt: "Search notes")
        }
    }
}

struct NoteRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(note.displayTitle)
                .lineLimit(1)
            if !note.preview.isEmpty {
                Text(note.preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 6) {
                Text(note.updatedAt.formatted(date: .abbreviated, time: .omitted))
                if !(note.links ?? []).isEmpty {
                    Image(systemName: "paperclip")
                        .accessibilityLabel("Attached to an event or reminder")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
