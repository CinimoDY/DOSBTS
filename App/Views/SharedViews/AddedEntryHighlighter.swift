//
//  AddedEntryHighlighter.swift
//  DOSBTS
//
//  Logging feedback: when an entry is logged, the row it lands on flashes
//  a brief phosphor glow so the user can follow what just happened instead
//  of the item silently appearing in the list. Injected at the app root
//  (alongside SheetCoordinator) so any list — recents in the entry sheet,
//  the Log tab's meal and insulin sections — can react to a log performed
//  anywhere, including from the coordinator's sheets.
//

import Combine
import SwiftUI

// MARK: - AddedEntryHighlighter

final class AddedEntryHighlighter: ObservableObject {
    /// The just-logged entry's id, cleared automatically after the flash
    /// window so the glow fades out on its own.
    @Published private(set) var highlightedID: UUID?

    /// How long the row stays lit before the fade-out starts.
    static let flashDuration: TimeInterval = 1.6

    private var clearTask: Task<Void, Never>?

    func flash(_ id: UUID) {
        clearTask?.cancel()
        highlightedID = id

        clearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.flashDuration))
            guard !Task.isCancelled else { return }
            self?.highlightedID = nil
        }
    }
}

// MARK: - Row highlight modifier

/// CGA-style "just logged" flash: the row lights up with a translucent
/// amber wash and a soft phosphor glow the instant the entry lands, then
/// fades out. Pure opacity animation — safe under Reduce Motion.
private struct DOSAddedHighlight: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .listRowBackground(
                AmberTheme.amber
                    .opacity(active ? 0.18 : 0)
                    .background(AmberTheme.dosBlack)
                    // Snap on, fade off: the flash should be instant when the
                    // entry lands and dissolve once the highlight clears.
                    .animation(active ? nil : AnimationTokens.highlightFade, value: active)
            )
            .shadow(
                color: AmberTheme.amber.opacity(active ? 0.5 : 0),
                radius: active ? 6 : 0, x: 0, y: 0
            )
            .animation(active ? nil : AnimationTokens.highlightFade, value: active)
    }
}

extension View {
    /// Apply to a List row; pass `highlighter.highlightedID == entry.id`.
    func dosAddedHighlight(_ active: Bool) -> some View {
        modifier(DOSAddedHighlight(active: active))
    }
}
