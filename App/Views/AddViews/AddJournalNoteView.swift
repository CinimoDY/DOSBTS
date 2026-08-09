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

                    // Voice capture (DMNC-1486). Journal notes are free prose, so
                    // there is no vocabulary worth biasing recognition toward.
                    DictationControl(contextualStrings: []) { transcript in
                        applyDictation(transcript)
                    }

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

    /// The note text as it stood before the current dictation was appended, so a
    /// re-spoken or edited transcript replaces its own tail instead of stacking.
    @State private var dictationBase: String?
    /// What we last wrote into `text`. If it no longer matches, the user typed in
    /// between and `dictationBase` is stale — the typing wins.
    @State private var lastDictationWrite: String?

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Append, never replace: the user may type first and then dictate more.
    /// `DictationControl` holds exactly one transcript and re-emits it on every
    /// edit, so the appended tail is rewritten in place rather than duplicated.
    private func applyDictation(_ transcript: String) {
        if lastDictationWrite != text {
            dictationBase = nil
        }
        let base = dictationBase ?? text

        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            // CLEAR: put the note back the way the user left it.
            text = base
            dictationBase = nil
            lastDictationWrite = base
            return
        }

        let needsSeparator = !base.isEmpty && !(base.last?.isWhitespace ?? false)
        let combined = base + (needsSeparator ? " " : "") + trimmed
        text = combined
        dictationBase = base
        lastDictationWrite = combined
    }
}
