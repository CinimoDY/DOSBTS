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
                if collapsible {
                    Button(action: toggle) {
                        headerRow(withChevron: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(collapsed ? "Expand" : "Collapse") \(sectionName), \(entryCountLabel)")
                } else {
                    // Empty section: a disabled button would dim the label and
                    // announce a dead "Expand" affordance — render plain instead.
                    headerRow(withChevron: false)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(sectionName), no entries")
                }

                Spacer()

                accessory
                    .buttonStyle(.plain)
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

    private func headerRow(withChevron: Bool) -> some View {
        HStack {
            // The label is the section's identity — it must never lose the
            // header's width fight. Without the priority + line limit, an
            // over-budget row (big count + chevron + date pager) squeezes the
            // label to ~1 character and wraps it letter-by-letter ("C/G" with
            // the "M" clipped, Build 132 dogfood report).
            label
                .lineLimit(1)
                .layoutPriority(1)
            Text(verbatim: "· \(count)")
                .font(DOSTypography.caption)
                .foregroundStyle(AmberTheme.amberDark)
                .fixedSize()
            if withChevron {
                Image(systemName: collapsed ? "chevron.down" : "chevron.up")
            }
        }
        // frame BEFORE contentShape so the 44pt tap target is hittable,
        // not just visual padding.
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    /// Localized pluralized count ("1 Entry" / "12 Entries") for VoiceOver —
    /// same keys the Lists teasers used.
    private var entryCountLabel: String {
        count.pluralizeLocalization(singular: "%@ Entry", plural: "%@ Entries")
    }

    private func toggle() {
        let newCollapsed = !collapsed
        collapsed = newCollapsed
        onCollapsedChange?(newCollapsed)
    }
}
