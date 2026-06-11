import Testing
import SwiftUI
@testable import DOSBTSApp

@Suite("AmberChip")
struct AmberChipTests {
    @Test("init stores selection state")
    func selectionStored() {
        let chip = AmberChip(label: "MEAL", isSelected: true) {}
        #expect(chip.isSelected == true)
    }

    @Test("quick variant stores subtitle and tint")
    func quickVariantStored() {
        let chip = AmberChip(
            label: "milk",
            subtitle: "12g",
            variant: .quick,
            tint: AmberTheme.cgaGreen
        ) {}
        #expect(chip.variant == .quick)
        #expect(chip.subtitle == "12g")
        #expect(chip.tint == AmberTheme.cgaGreen)
    }

    @Test("subtitle defaults to nil for existing call sites")
    func subtitleDefaultsNil() {
        let chip = AmberChip(label: "MEAL") {}
        #expect(chip.subtitle == nil)
    }

    @Test("label-only view carries the same visual inputs as the chip")
    func labelViewStored() {
        let label = AmberChipLabel(label: "milk", subtitle: "12g", variant: .quick)
        #expect(label.variant == .quick)
        #expect(label.subtitle == "12g")
        #expect(label.isSelected == false)
    }
}

// MARK: - Caption Legibility (R5/AE3)

/// Pins the contrast math behind the amberDark → amber caption migration:
/// informational small text now renders `amber`, which must satisfy WCAG AA
/// on the pure-black background; `amberDark` deliberately stays the dim
/// token (R5: "amberDark itself is not mutated") so dimming/disabled roles
/// keep their subordinated look.
@Suite("Caption legibility tokens")
struct CaptionLegibilityTests {
    /// WCAG relative luminance for sRGB components in 0...1.
    private func luminance(r: Double, g: Double, b: Double) -> Double {
        func lin(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    private func contrastOnBlack(r: Double, g: Double, b: Double) -> Double {
        (luminance(r: r, g: g, b: b) + 0.05) / 0.05
    }

    @Test("amber on black meets AA for normal text (>=4.5:1)")
    func amberMeetsAA() {
        // #ffb000 — the published AmberTheme.amber token value
        let ratio = contrastOnBlack(r: 1.0, g: 176.0 / 255.0, b: 0)
        #expect(ratio >= 4.5)

        // Pin the token itself so a silent token change re-runs this math
        let resolved = UIColor(AmberTheme.amber)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(abs(r - 1.0) < 0.001)
        #expect(abs(g - 176.0 / 255.0) < 0.001)
        #expect(abs(b - 0.0) < 0.001)
        #expect(contrastOnBlack(r: r, g: g, b: b) >= 4.5)
    }

    @Test("amberDark stays the dim token (below AA — reserved for dimming)")
    func amberDarkStaysDim() {
        let resolved = UIColor(AmberTheme.amberDark)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        // #9a5700 — if this ever passes AA someone brightened the dim token
        // instead of migrating call sites; that breaks the dimming hierarchy.
        #expect(abs(r - 154.0 / 255.0) < 0.001)
        #expect(abs(g - 87.0 / 255.0) < 0.001)
        #expect(contrastOnBlack(r: r, g: g, b: b) < 4.5)
    }
}
