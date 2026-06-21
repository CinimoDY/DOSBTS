//
//  DOSModifiers.swift
//  DOSBTS
//
//  App-only view modifiers for the DOS CGA skin.
//

import SwiftUI

// MARK: - DOS Navigation Title

/// CGA-styled navigation title: amber-light monospace, always inline.
///
/// iOS 26's SwiftUI navigation bar ignores `UINavigationBar.appearance()`
/// title attributes, so system titles render white. This modifier keeps
/// `.navigationTitle` for semantics (back-button labels, VoiceOver) and
/// overrides the visible title with a principal toolbar item in the
/// phosphor palette.
private struct DOSNavigationTitle: ViewModifier {
    let title: Text

    func body(content: Content) -> some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    title
                        .font(DOSTypography.mono(size: 14, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(AmberTheme.amberLight)
                }
            }
    }
}

extension View {
    func dosNavigationTitle(_ titleKey: LocalizedStringKey) -> some View {
        navigationTitle(titleKey)
            .modifier(DOSNavigationTitle(title: Text(titleKey)))
    }

    func dosNavigationTitle(_ title: String) -> some View {
        navigationTitle(title)
            .modifier(DOSNavigationTitle(title: Text(verbatim: title)))
    }
}

// MARK: - Staged reveal

extension View {
    /// A block stays invisible until its stage index is revealed by the
    /// parent's monotonically-increasing reveal counter — the building block of
    /// the digest insight cascade and the What's New patch-notes cards
    /// (DMNC-1147). Step the counter with `Task`-spaced `withAnimation` writes
    /// (not a synchronous loop) so same-tick writes don't coalesce into one
    /// fade; jump straight to the final count under Reduce Motion.
    func stagedReveal(_ stage: Int, revealed: Int) -> some View {
        opacity(revealed > stage ? 1 : 0)
    }
}
