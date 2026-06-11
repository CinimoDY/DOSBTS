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
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
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
