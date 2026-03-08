//
//  DOSSpacing.swift
//  DOSBTS
//
//  DOS-Inspired Spacing System
//

import SwiftUI

/// Spacing scale for consistent layout throughout the app
public enum DOSSpacing {
    /// 4pt - Icon-to-label, internal gaps
    public static let xxs: CGFloat = 4

    /// 8pt - Compact list row padding
    public static let xs: CGFloat = 8

    /// 12pt - Card internal padding
    public static let sm: CGFloat = 12

    /// 16pt - Standard section spacing
    public static let md: CGFloat = 16

    /// 24pt - Between cards/groups
    public static let lg: CGFloat = 24

    /// 32pt - Major section breaks
    public static let xl: CGFloat = 32

    /// 48pt - Screen-level padding
    public static let xxl: CGFloat = 48

    /// 64pt - Hero content breathing room
    public static let hero: CGFloat = 64
}
