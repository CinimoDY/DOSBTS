//
//  DOSTabBarAppearance.swift
//  DOSBTS
//

import SwiftUI
import UIKit

/// Factory for the app's tab bar item appearance (DMNC-1029).
///
/// Builds a fully-themed `UITabBarAppearance`: opaque black background,
/// unselected items in dim `amberDark`, selected items in bright `amber`,
/// applied to all three layout appearances (stacked / inline / compact).
///
/// ⚠️ EMPIRICAL FINDING (iOS 26.5, verified DMNC-1167): the iOS 26 SwiftUI
/// `TabView` Liquid Glass bar **ignores `UITabBar.appearance()` entirely** —
/// not just the convenience `unselectedItemTintColor`, but the granular
/// per-state `UITabBarItemAppearance` colors *and* even `backgroundColor`,
/// whether the proxy is installed in `onAppear` or in `App.init()` (before the
/// bar exists). A diagnostic build with cyan unselected icons + a blue
/// background produced no on-screen change. Unselected tab labels/icons
/// therefore stay the system secondary color; the selected tint comes from
/// SwiftUI's root `.tint(AmberTheme.amber)` (App.swift), not from this object.
/// There is no SwiftUI-native unselected-item color API. See
/// `docs/solutions/best-practices/ios-26-liquid-glass-theming-gotchas.md` (#4).
///
/// This configuration is retained as the correct, most-specific UIKit
/// appearance (matching the nav-bar pattern) and is forward-compatible should
/// a future OS point release start honoring the proxy, or should a
/// UIKit-backed tab surface ever consume it. It is currently inert under the
/// iOS 26 SwiftUI TabView. Extracted as a pure factory so the token→state
/// mapping stays unit-assertable — see `DOSTabBarAppearanceTests`.
enum DOSTabBarAppearance {
    static func make() -> UITabBarAppearance {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .black

        let item = UITabBarItemAppearance()
        item.normal.iconColor = UIColor(AmberTheme.amberDark)
        item.normal.titleTextAttributes = [.foregroundColor: UIColor(AmberTheme.amberDark)]
        item.selected.iconColor = UIColor(AmberTheme.amber)
        item.selected.titleTextAttributes = [.foregroundColor: UIColor(AmberTheme.amber)]

        appearance.stackedLayoutAppearance = item
        appearance.inlineLayoutAppearance = item
        appearance.compactInlineLayoutAppearance = item
        return appearance
    }
}
