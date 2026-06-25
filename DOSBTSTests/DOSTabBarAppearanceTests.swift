import Testing
import SwiftUI
import UIKit
@testable import DOSBTSApp

/// Pins the tab bar appearance factory's token→state mapping (DMNC-1029).
///
/// Guards against a future token swap silently un-theming the bar. This proves
/// the color mapping only — it does NOT prove the on-screen result under the
/// iOS 26 Liquid Glass bar (that is the build-and-observe verification gate).
@Suite("DOS Tab Bar Appearance")
struct DOSTabBarAppearanceTests {
    private let tolerance: CGFloat = 0.001

    private func rgb(_ color: UIColor) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b)
    }

    private func expectMatches(_ color: UIColor?, _ token: Color, _ label: String) {
        guard let color else {
            Issue.record("\(label) color was nil")
            return
        }
        let actual = rgb(color)
        let expected = rgb(UIColor(token))
        #expect(abs(actual.r - expected.r) < tolerance, "\(label) red channel")
        #expect(abs(actual.g - expected.g) < tolerance, "\(label) green channel")
        #expect(abs(actual.b - expected.b) < tolerance, "\(label) blue channel")
    }

    private func titleColor(_ item: UITabBarItemStateAppearance) -> UIColor? {
        item.titleTextAttributes[.foregroundColor] as? UIColor
    }

    @Test("unselected (normal) icon + title pin to amberDark for the stacked layout")
    func normalStateUsesAmberDark() {
        let stacked = DOSTabBarAppearance.make().stackedLayoutAppearance
        expectMatches(stacked.normal.iconColor, AmberTheme.amberDark, "normal icon")
        expectMatches(titleColor(stacked.normal), AmberTheme.amberDark, "normal title")
    }

    @Test("selected icon + title pin to amber for the stacked layout")
    func selectedStateUsesAmber() {
        let stacked = DOSTabBarAppearance.make().stackedLayoutAppearance
        expectMatches(stacked.selected.iconColor, AmberTheme.amber, "selected icon")
        expectMatches(titleColor(stacked.selected), AmberTheme.amber, "selected title")
    }

    @Test("all three layout appearances carry the same item icon + title colors")
    func allLayoutsConfigured() {
        let appearance = DOSTabBarAppearance.make()
        for layout in [appearance.stackedLayoutAppearance,
                       appearance.inlineLayoutAppearance,
                       appearance.compactInlineLayoutAppearance] {
            expectMatches(layout.normal.iconColor, AmberTheme.amberDark, "normal icon")
            expectMatches(titleColor(layout.normal), AmberTheme.amberDark, "normal title")
            expectMatches(layout.selected.iconColor, AmberTheme.amber, "selected icon")
            expectMatches(titleColor(layout.selected), AmberTheme.amber, "selected title")
        }
    }
}
