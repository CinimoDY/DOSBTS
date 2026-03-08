//
//  AmberTheme.swift
//  DOSBTS
//
//  eiDotter CGA Amber Design System - iOS Token Mapping
//  Source: https://github.com/CinimoDY/eiDotter
//

import SwiftUI

/// eiDotter CGA Amber Theme - Token-aligned color definitions
public enum AmberTheme {

    // MARK: - Primary Amber Colors (eiDotter tokens)

    /// --color-cga-amber: #ffb000 - P3 phosphor amber (602nm)
    public static let amber = Color(red: 1.0, green: 176.0 / 255.0, blue: 0)

    /// --color-cga-amber-dim: #9a5700 - Secondary text, dimmed states (18pt+ only)
    public static let amberDark = Color(red: 154.0 / 255.0, green: 87.0 / 255.0, blue: 0)

    /// --color-cga-amber-bright: #fdca9f - Highlights, focus states
    public static let amberLight = Color(red: 253.0 / 255.0, green: 202.0 / 255.0, blue: 159.0 / 255.0)

    /// Pressed button state: #CC8C00
    public static let amberPressed = Color(red: 204.0 / 255.0, green: 140.0 / 255.0, blue: 0)

    /// --color-cga-dark-gray: #555555 - Disabled states, muted
    public static let amberMuted = Color(red: 85.0 / 255.0, green: 85.0 / 255.0, blue: 85.0 / 255.0)

    // MARK: - CGA 16-Color Palette (eiDotter tokens)

    /// --color-cga-bright-green: #55ff55
    public static let cgaGreen = Color(red: 85.0 / 255.0, green: 1.0, blue: 85.0 / 255.0)

    /// --color-cga-bright-cyan: #55ffff
    public static let cgaCyan = Color(red: 85.0 / 255.0, green: 1.0, blue: 1.0)

    /// --color-cga-bright-red: #ff5555
    public static let cgaRed = Color(red: 1.0, green: 85.0 / 255.0, blue: 85.0 / 255.0)

    /// --color-cga-white: #aaaaaa
    public static let cgaWhite = Color(red: 170.0 / 255.0, green: 170.0 / 255.0, blue: 170.0 / 255.0)

    // MARK: - DOS Terminal Background Colors

    /// --color-cga-black: #000000
    public static let dosBlack = Color(red: 0, green: 0, blue: 0)

    /// Warm dark gray for borders and separators: #594F47
    public static let dosBorder = Color(red: 89.0 / 255.0, green: 79.0 / 255.0, blue: 71.0 / 255.0)

    /// Warm near-black for card backgrounds: #1B1917
    public static let cardBackground = Color(red: 27.0 / 255.0, green: 25.0 / 255.0, blue: 23.0 / 255.0)
}
