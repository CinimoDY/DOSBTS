//
//  AddJournalNoteView.swift
//  DOSBTSApp
//

import SwiftUI

/// Owns its own NavigationStack because RootSheetContent presents it directly
/// (contrast AddMealView, which is *pushed* and therefore has none).
///
/// The view is deliberately dumb: it validates and hands values back through
/// `addCallback`. Building the model, dispatching, flashing the highlighter and
/// firing the haptic all live in RootSheetContent — no DirectStore access here.
struct AddJournalNoteView: View {
    @Environment(\.dismiss) var dismiss

    @State var timestamp: Date = .init()

    var addCallback: (_ timestamp: Date, _ text: String, _ tag: JournalNoteTag?) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section(content: {
                    TextField("What's going on?", text: $text, axis: .vertical)
                        .lineLimit(3 ... 6)
                        .focused($textFocus)

                    DatePicker(
                        "Time",
                        selection: $timestamp,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }, footer: {
                    Text("Context the numbers can't show — illness, stress, bad sleep. Backdate with the time picker.")
                        .font(DOSTypography.caption)
                        .foregroundStyle(AmberTheme.amber)
                })
                .listRowBackground(AmberTheme.dosBlack)
                .listRowSeparatorTint(AmberTheme.borderFaint)

                Section(content: {
                    // Two columns rather than one row of four: "STRESSED" and
                    // "SLUGGISH" truncate at a quarter of the Form row width.
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: DOSSpacing.xs),
                        GridItem(.flexible(), spacing: DOSSpacing.xs),
                    ], spacing: DOSSpacing.xs) {
                        ForEach(JournalNoteTag.allCases) { option in
                            AmberChip(
                                label: option.localizedDescription,
                                variant: .type,
                                isSelected: tag == option,
                                action: { tag = (tag == option) ? nil : option }
                            )
                        }
                    }
                    .padding(.vertical, DOSSpacing.xxs)
                }, footer: {
                    Text("Optional. Tap the selected tag again to clear it.")
                        .font(DOSTypography.caption)
                        .foregroundStyle(AmberTheme.amber)
                })
                .listRowBackground(AmberTheme.dosBlack)
                .listRowSeparatorTint(AmberTheme.borderFaint)
            }
            .scrollContentBackground(.hidden)
            .background(AmberTheme.dosBlack.ignoresSafeArea())
            .dosNavigationTitle("Note")
            // Suppress the system back button so Cancel is the sole leading
            // control, and block swipe-to-dismiss so a half-typed note isn't
            // silently discarded — Cancel/Add are the way out.
            .navigationBarBackButtonHidden(true)
            .interactiveDismissDisabled()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        let clamped = JournalNote.clamp(text)
                        guard !clamped.isEmpty else { return }
                        addCallback(timestamp, clamped, tag)
                        dismiss()
                    }
                    .disabled(trimmedText.isEmpty)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now()) {
                    self.textFocus = true
                }
            }
        }
    }

    // MARK: Private

    @FocusState private var textFocus: Bool

    @State private var text: String = ""
    @State private var tag: JournalNoteTag?

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
