//
//  JournalNoteListView.swift
//  DOSBTSApp
//

import SwiftUI

struct JournalNoteListView: View {
    /// UserDefaults persistence key for this section's expanded state —
    /// must stay stable across releases (display name may change freely).
    private let sectionKey = "Journal notes"

    // MARK: Internal

    @EnvironmentObject var store: DirectStore
    @EnvironmentObject var addedHighlighter: AddedEntryHighlighter

    var body: some View {
        Group {
            CollapsableSection(
                label: Label("Notes", systemImage: "square.and.pencil"),
                accessory: SelectedDatePager().padding(.trailing),
                sectionName: "Notes",
                count: journalNoteValues.count,
                collapsed: !store.state.listSectionExpanded[sectionKey, default: false],
                collapsible: !journalNoteValues.isEmpty,
                onCollapsedChange: { isCollapsed in
                    store.dispatch(.setListSectionExpanded(sectionName: sectionKey, isExpanded: !isCollapsed))
                })
            {
                if !journalNoteValues.isEmpty {
                    ForEach(journalNoteValues) { note in
                        VStack(alignment: .leading, spacing: DOSSpacing.xxs) {
                            HStack {
                                Text(verbatim: note.timestamp.toLocalDateTime())
                                    .monospacedDigit()

                                Spacer()

                                if let tag = note.tag {
                                    Text(verbatim: tag.localizedDescription)
                                        .font(DOSTypography.caption)
                                        .foregroundStyle(AmberTheme.amberDark)
                                }
                            }

                            // User-authored: `verbatim` so nothing in the note
                            // is read as a localization key or markdown.
                            Text(verbatim: note.text)
                                .lineLimit(2)
                                .truncationMode(.tail)
                        }
                        .dosAddedHighlight(addedHighlighter.highlightedID == note.id)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                delete(note)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.grouped)
        .onAppear {
            self.journalNoteValues = store.state.journalNoteValues.reversed()
        }
        .onChange(of: store.state.journalNoteValues) { _, journalNoteValues in
            self.journalNoteValues = journalNoteValues.reversed()
        }
    }

    // MARK: Private

    /// Local mirror of the store array, newest first. It exists so swipe-delete
    /// can remove the row optimistically — without it the row snaps back while
    /// the delete → reload dispatch round-trips through GRDB.
    @State private var journalNoteValues: [JournalNote] = []

    private func delete(_ note: JournalNote) {
        DirectLog.info("delete journal note: \(note.id)")
        journalNoteValues.removeAll { $0.id == note.id }
        store.dispatch(.deleteJournalNote(journalNote: note))
    }
}
