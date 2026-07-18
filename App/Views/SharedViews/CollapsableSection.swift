//
//  CollapsableSection.swift
//  DOSBTSApp
//

import SwiftUI

// MARK: - CollapsableSection

struct CollapsableSection<Label, Accessory, Content>: View where Label: View, Accessory: View, Content: View {
    // MARK: Lifecycle

    init(label: Label, accessory: Accessory, sectionName: String = "section", count: Int, collapsed: Bool = false, collapsible: Bool = true, onCollapsedChange: ((Bool) -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.accessory = accessory
        self.sectionName = sectionName
        self.count = count
        // One-way seed: `collapsed` initializes local @State but is not re-read
        // afterwards — the section is its own only writer (via onCollapsedChange).
        // If an external writer of the persisted state ever appears (e.g. a
        // "collapse all" action), this must become a real two-way binding.
        self._collapsed = State(initialValue: collapsed)
        self.collapsible = collapsible
        self.onCollapsedChange = onCollapsedChange
        self.content = content
    }

    // MARK: Internal

    let label: Label
    /// Rendered outside the toggle button as its own hit region (e.g.
    /// `SelectedDatePager`'s prev/next buttons must not collapse the section).
    let accessory: Accessory
    let content: () -> Content
    /// Names the section in the toggle button's VoiceOver label
    /// ("Expand Meals, 12 entries") so multiple sections stay distinguishable.
    let sectionName: String
    let count: Int

    var body: some View {
        Section(
            header: HStack {
                Button(action: toggle) {
                    HStack {
                        label
                        Text(verbatim: "· \(count)")
                            .font(DOSTypography.caption)
                            .foregroundStyle(AmberTheme.amberDark)
                        Image(systemName: collapsed ? "chevron.down" : "chevron.up")
                            .opacity(collapsible ? 1 : 0)
                    }
                    .contentShape(Rectangle())
                    .frame(minHeight: 44)
                }
                .disabled(!collapsible)
                .buttonStyle(.plain)
                .accessibilityLabel("\(collapsed ? "Expand" : "Collapse") \(sectionName), \(count) entries")

                Spacer()

                accessory
            }
        ) {
            if !collapsed {
                content()
            }
        }
    }

    // MARK: Private

    @State private var collapsed: Bool
    private var collapsible: Bool
    private let onCollapsedChange: ((Bool) -> Void)?

    private func toggle() {
        let newCollapsed = !collapsed
        collapsed = newCollapsed
        onCollapsedChange?(newCollapsed)
    }
}
