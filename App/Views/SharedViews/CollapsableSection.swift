//
//  CollapsableSection.swift
//  DOSBTSApp
//

import SwiftUI

// MARK: - CollapsableSection

struct CollapsableSection<Parent, Content, Teaser>: View where Parent: View, Content: View, Teaser: View {
    // MARK: Lifecycle

    init(teaser: Teaser, header: Parent, sectionName: String = "section", collapsed: Bool = false, collapsible: Bool = true, @ViewBuilder content: @escaping () -> Content) {
        self.teaser = teaser
        self.header = header
        self.sectionName = sectionName
        self._collapsed = State(initialValue: collapsed)
        self.collapsible = collapsible
        self.content = content
    }

    // MARK: Internal

    let header: Parent
    let content: () -> Content
    let teaser: Teaser
    /// Names the section in the teaser button's VoiceOver label
    /// ("Expand Meals") so multiple collapsed sections stay distinguishable.
    let sectionName: String

    var body: some View {
        Section(
            header: HStack {
                header
                Spacer()

                Button(action: {
                    collapsed.toggle()
                }, label: {
                    Image(systemName: collapsed ? "chevron.up" : "chevron.down")
                })
                .disabled(!collapsible)
                .opacity(collapsible ? 1 : 0)
                .buttonStyle(.plain)
            }
        ) {
            Group {
                if collapsed, collapsible {
                    // The teaser row ("675 Entries") is the obvious thing to
                    // tap — expanding shouldn't require hitting the small
                    // chevron in the header.
                    Button {
                        collapsed = false
                    } label: {
                        HStack {
                            teaser
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(DOSTypography.caption)
                                .foregroundColor(AmberTheme.amberDark)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Expand \(sectionName)")
                } else if collapsed {
                    // Empty/non-collapsible sections show the bare teaser —
                    // no dead chevron affordance.
                    teaser
                } else {
                    content()
                }
            }
        }
    }

    // MARK: Private

    @State private var collapsed: Bool
    private var collapsible: Bool
}

extension CollapsableSection where Teaser == EmptyView {
    init(header: Parent, collapsed: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.init(teaser: EmptyView(), header: header, collapsed: collapsed, content: content)
    }
}
