import Testing
import SwiftUI
import UIKit
@testable import DOSBTSApp

@Suite("Design Token Drift Guard")
struct DesignTokenPinTests {
    private let tolerance: CGFloat = 0.001

    // MARK: - AmberTheme Color Pins

    @Test("amber token pins to #ffb000")
    func amberColorPin() {
        let color = UIColor(AmberTheme.amber)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(abs(r - 1.0) < tolerance)
        #expect(abs(g - 176.0 / 255.0) < tolerance)
        #expect(abs(b - 0.0) < tolerance)
    }

    @Test("amberDark token pins to #9a5700 (R+G+B)")
    func amberDarkColorPin() {
        let color = UIColor(AmberTheme.amberDark)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(abs(r - 154.0 / 255.0) < tolerance)
        #expect(abs(g - 87.0 / 255.0) < tolerance)
        #expect(abs(b - 0.0) < tolerance, "amberDark blue channel should remain 0.0")
    }

    @Test("amberLight token pins to #fdca9f")
    func amberLightColorPin() {
        let color = UIColor(AmberTheme.amberLight)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(abs(r - 253.0 / 255.0) < tolerance)
        #expect(abs(g - 202.0 / 255.0) < tolerance)
        #expect(abs(b - 159.0 / 255.0) < tolerance)
    }

    @Test("amberPressed token pins to #CC8C00")
    func amberPressedColorPin() {
        let color = UIColor(AmberTheme.amberPressed)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(abs(r - 204.0 / 255.0) < tolerance)
        #expect(abs(g - 140.0 / 255.0) < tolerance)
        #expect(abs(b - 0.0) < tolerance)
    }

    @Test("amberMuted token pins to #555555")
    func amberMutedColorPin() {
        let color = UIColor(AmberTheme.amberMuted)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(abs(r - 85.0 / 255.0) < tolerance)
        #expect(abs(g - 85.0 / 255.0) < tolerance)
        #expect(abs(b - 85.0 / 255.0) < tolerance)
    }

    @Test("cgaGreen token pins to #55ff55")
    func cgaGreenColorPin() {
        let color = UIColor(AmberTheme.cgaGreen)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(abs(r - 85.0 / 255.0) < tolerance)
        #expect(abs(g - 1.0) < tolerance)
        #expect(abs(b - 85.0 / 255.0) < tolerance)
    }

    @Test("cgaCyan token pins to #55ffff")
    func cgaCyanColorPin() {
        let color = UIColor(AmberTheme.cgaCyan)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(abs(r - 85.0 / 255.0) < tolerance)
        #expect(abs(g - 1.0) < tolerance)
        #expect(abs(b - 1.0) < tolerance)
    }

    @Test("cgaRed token pins to #ff5555")
    func cgaRedColorPin() {
        let color = UIColor(AmberTheme.cgaRed)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(abs(r - 1.0) < tolerance)
        #expect(abs(g - 85.0 / 255.0) < tolerance)
        #expect(abs(b - 85.0 / 255.0) < tolerance)
    }

    @Test("cgaMagenta token pins to #ff55ff")
    func cgaMagentaColorPin() {
        let color = UIColor(AmberTheme.cgaMagenta)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(abs(r - 1.0) < tolerance)
        #expect(abs(g - 85.0 / 255.0) < tolerance)
        #expect(abs(b - 1.0) < tolerance)
    }

    @Test("cgaWhite token pins to #aaaaaa")
    func cgaWhiteColorPin() {
        let color = UIColor(AmberTheme.cgaWhite)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(abs(r - 170.0 / 255.0) < tolerance)
        #expect(abs(g - 170.0 / 255.0) < tolerance)
        #expect(abs(b - 170.0 / 255.0) < tolerance)
    }

    @Test("dosBlack token pins to #000000")
    func dosBlackColorPin() {
        let color = UIColor(AmberTheme.dosBlack)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(abs(r - 0.0) < tolerance)
        #expect(abs(g - 0.0) < tolerance)
        #expect(abs(b - 0.0) < tolerance)
    }

    @Test("dosBorder token pins to #594F47")
    func dosBorderColorPin() {
        let color = UIColor(AmberTheme.dosBorder)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(abs(r - 89.0 / 255.0) < tolerance)
        #expect(abs(g - 79.0 / 255.0) < tolerance)
        #expect(abs(b - 71.0 / 255.0) < tolerance)
    }

    @Test("cardBackground token pins to #1B1917")
    func cardBackgroundColorPin() {
        let color = UIColor(AmberTheme.cardBackground)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(abs(r - 27.0 / 255.0) < tolerance)
        #expect(abs(g - 25.0 / 255.0) < tolerance)
        #expect(abs(b - 23.0 / 255.0) < tolerance)
    }

    @Test("iobBolus token pins to #8CBF40")
    func iobBolusColorPin() {
        let color = UIColor(AmberTheme.iobBolus)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(abs(r - 140.0 / 255.0) < tolerance)
        #expect(abs(g - 191.0 / 255.0) < tolerance)
        #expect(abs(b - 64.0 / 255.0) < tolerance)
    }

    @Test("iobBasal token pins to #5DD0F3")
    func iobBasalColorPin() {
        let color = UIColor(AmberTheme.iobBasal)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(abs(r - 93.0 / 255.0) < tolerance)
        #expect(abs(g - 208.0 / 255.0) < tolerance)
        #expect(abs(b - 243.0 / 255.0) < tolerance)
    }

    // MARK: - Semantic Tier Token Pins (blended; alpha-channel included)

    @Test("borderFaint pins to amberDark @ alpha 0.3")
    func borderFaintPin() {
        let color = UIColor(AmberTheme.borderFaint)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(abs(r - 154.0 / 255.0) < tolerance)
        #expect(abs(g - 87.0 / 255.0) < tolerance)
        #expect(abs(b - 0.0) < tolerance)
        #expect(abs(a - 0.3) < tolerance)
    }

    @Test("borderSubtle pins to amberDark @ alpha 0.4")
    func borderSubtlePin() {
        let color = UIColor(AmberTheme.borderSubtle)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(abs(r - 154.0 / 255.0) < tolerance)
        #expect(abs(g - 87.0 / 255.0) < tolerance)
        #expect(abs(b - 0.0) < tolerance)
        #expect(abs(a - 0.4) < tolerance)
    }

    @Test("borderStrong pins to amberDark @ alpha 0.6")
    func borderStrongPin() {
        let color = UIColor(AmberTheme.borderStrong)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(abs(r - 154.0 / 255.0) < tolerance)
        #expect(abs(g - 87.0 / 255.0) < tolerance)
        #expect(abs(b - 0.0) < tolerance)
        #expect(abs(a - 0.6) < tolerance)
    }

    @Test("textFaint pins to amberDark @ alpha 0.7")
    func textFaintPin() {
        let color = UIColor(AmberTheme.textFaint)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(abs(r - 154.0 / 255.0) < tolerance)
        #expect(abs(g - 87.0 / 255.0) < tolerance)
        #expect(abs(b - 0.0) < tolerance)
        #expect(abs(a - 0.7) < tolerance)
    }

    @Test("surfaceTint pins to amber @ alpha 0.04")
    func surfaceTintPin() {
        let color = UIColor(AmberTheme.surfaceTint)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(abs(r - 1.0) < tolerance)
        #expect(abs(g - 176.0 / 255.0) < tolerance)
        #expect(abs(b - 0.0) < tolerance)
        #expect(abs(a - 0.04) < tolerance)
    }

    @Test("scrim pins to dosBlack @ alpha 0.7")
    func scrimPin() {
        let color = UIColor(AmberTheme.scrim)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(abs(r - 0.0) < tolerance)
        #expect(abs(g - 0.0) < tolerance)
        #expect(abs(b - 0.0) < tolerance)
        #expect(abs(a - 0.7) < tolerance)
    }

    @Test("scrimHeavy pins to dosBlack @ alpha 0.95")
    func scrimHeavyPin() {
        let color = UIColor(AmberTheme.scrimHeavy)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(abs(r - 0.0) < tolerance)
        #expect(abs(g - 0.0) < tolerance)
        #expect(abs(b - 0.0) < tolerance)
        #expect(abs(a - 0.95) < tolerance)
    }

    @Test("inkOnAmber pins to dosBlack (opaque black)")
    func inkOnAmberPin() {
        let color = UIColor(AmberTheme.inkOnAmber)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(abs(r - 0.0) < tolerance)
        #expect(abs(g - 0.0) < tolerance)
        #expect(abs(b - 0.0) < tolerance)
        #expect(abs(a - 1.0) < tolerance)
    }

    // MARK: - DOSTypography Micro Scale Pins

    @Test("micro font pins to 9pt regular monospaced")
    func microFontPin() {
        #expect(DOSTypography.micro == Font.system(size: 9, weight: .regular, design: .monospaced))
    }

    @Test("microLabel font pins to 10pt medium monospaced")
    func microLabelFontPin() {
        #expect(DOSTypography.microLabel == Font.system(size: 10, weight: .medium, design: .monospaced))
    }

    @Test("label font pins to 11pt medium monospaced")
    func labelFontPin() {
        #expect(DOSTypography.label == Font.system(size: 11, weight: .medium, design: .monospaced))
    }

    @Test("numeral font pins to 24pt semibold monospaced")
    func numeralFontPin() {
        #expect(DOSTypography.numeral == Font.system(size: 24, weight: .semibold, design: .monospaced))
    }

    // MARK: - DOSTypography Font Size Pins

    @Test("displayMedium font pins to 28pt bold monospaced")
    func displayMediumFontPin() {
        #expect(DOSTypography.displayMedium == Font.system(size: 28, weight: .bold, design: .monospaced))
    }

    @Test("glucoseHero font pins to 60pt bold monospaced with monospacedDigit")
    func glucoseHeroFontPin() {
        #expect(DOSTypography.glucoseHero == Font.system(size: 60, weight: .bold, design: .monospaced).monospacedDigit())
    }

    @Test("bodyLarge font pins to 20pt regular monospaced")
    func bodyLargeFontPin() {
        #expect(DOSTypography.bodyLarge == Font.system(size: 20, weight: .regular, design: .monospaced))
    }

    @Test("body font pins to 17pt regular monospaced")
    func bodyFontPin() {
        #expect(DOSTypography.body == Font.system(size: 17, weight: .regular, design: .monospaced))
    }

    @Test("bodySmall font pins to 15pt regular monospaced")
    func bodySmallFontPin() {
        #expect(DOSTypography.bodySmall == Font.system(size: 15, weight: .regular, design: .monospaced))
    }

    @Test("caption font pins to 12pt regular monospaced")
    func captionFontPin() {
        #expect(DOSTypography.caption == Font.system(size: 12, weight: .regular, design: .monospaced))
    }

    @Test("button font pins to 17pt semibold monospaced")
    func buttonFontPin() {
        #expect(DOSTypography.button == Font.system(size: 17, weight: .semibold, design: .monospaced))
    }

    @Test("tabBar font pins to 10pt medium monospaced")
    func tabBarFontPin() {
        #expect(DOSTypography.tabBar == Font.system(size: 10, weight: .medium, design: .monospaced))
    }

    // MARK: - DOSSpacing Value Pins

    @Test("DOSSpacing.xxs pins to 4pt")
    func spacingXXSPin() {
        #expect(DOSSpacing.xxs == 4)
    }

    @Test("DOSSpacing.xs pins to 8pt")
    func spacingXSPin() {
        #expect(DOSSpacing.xs == 8)
    }

    @Test("DOSSpacing.sm pins to 12pt")
    func spacingSMPin() {
        #expect(DOSSpacing.sm == 12)
    }

    @Test("DOSSpacing.md pins to 16pt")
    func spacingMDPin() {
        #expect(DOSSpacing.md == 16)
    }

    @Test("DOSSpacing.lg pins to 24pt")
    func spacingLGPin() {
        #expect(DOSSpacing.lg == 24)
    }

    @Test("DOSSpacing.xl pins to 32pt")
    func spacingXLPin() {
        #expect(DOSSpacing.xl == 32)
    }

    @Test("DOSSpacing.xxl pins to 48pt")
    func spacingXXLPin() {
        #expect(DOSSpacing.xxl == 48)
    }

    @Test("DOSSpacing.hero pins to 64pt")
    func spacingHeroPin() {
        #expect(DOSSpacing.hero == 64)
    }

    // MARK: - DOSCardVariant fill / stroke mapping (DMNC-1216)

    /// Straight RGBA of a SwiftUI `Color`, for variant-mapping assertions.
    private func rgba(_ color: Color) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }

    @Test("DOSCardVariant.panel maps to cardBackground fill + dosBorder stroke")
    func panelVariantPin() {
        let fill = rgba(DOSCardVariant.panel.fill)
        #expect(abs(fill.r - 27.0 / 255.0) < tolerance)
        #expect(abs(fill.g - 25.0 / 255.0) < tolerance)
        #expect(abs(fill.b - 23.0 / 255.0) < tolerance)
        #expect(abs(fill.a - 1.0) < tolerance)
        let stroke = rgba(DOSCardVariant.panel.stroke)
        #expect(abs(stroke.r - 89.0 / 255.0) < tolerance)
        #expect(abs(stroke.g - 79.0 / 255.0) < tolerance)
        #expect(abs(stroke.b - 71.0 / 255.0) < tolerance)
        #expect(abs(stroke.a - 1.0) < tolerance)
    }

    @Test("DOSCardVariant.info maps to clear fill + cgaCyan stroke")
    func infoVariantPin() {
        let fill = rgba(DOSCardVariant.info.fill)
        #expect(abs(fill.a - 0.0) < tolerance, "info fill is clear")
        let stroke = rgba(DOSCardVariant.info.stroke)
        #expect(abs(stroke.r - 85.0 / 255.0) < tolerance)
        #expect(abs(stroke.g - 1.0) < tolerance)
        #expect(abs(stroke.b - 1.0) < tolerance)
        #expect(abs(stroke.a - 1.0) < tolerance)
    }

    @Test("DOSCardVariant.stat maps to surfaceTint fill + borderSubtle stroke")
    func statVariantPin() {
        let fill = rgba(DOSCardVariant.stat.fill)
        #expect(abs(fill.r - 1.0) < tolerance)
        #expect(abs(fill.g - 176.0 / 255.0) < tolerance)
        #expect(abs(fill.b - 0.0) < tolerance)
        #expect(abs(fill.a - 0.04) < tolerance)
        let stroke = rgba(DOSCardVariant.stat.stroke)
        #expect(abs(stroke.r - 154.0 / 255.0) < tolerance)
        #expect(abs(stroke.g - 87.0 / 255.0) < tolerance)
        #expect(abs(stroke.b - 0.0) < tolerance)
        #expect(abs(stroke.a - 0.4) < tolerance)
    }

    @Test("DOSCardVariant.toast maps to dosBlack fill + amber stroke")
    func toastVariantPin() {
        let fill = rgba(DOSCardVariant.toast.fill)
        #expect(abs(fill.r - 0.0) < tolerance)
        #expect(abs(fill.g - 0.0) < tolerance)
        #expect(abs(fill.b - 0.0) < tolerance)
        #expect(abs(fill.a - 1.0) < tolerance)
        let stroke = rgba(DOSCardVariant.toast.stroke)
        #expect(abs(stroke.r - 1.0) < tolerance)
        #expect(abs(stroke.g - 176.0 / 255.0) < tolerance)
        #expect(abs(stroke.b - 0.0) < tolerance)
        #expect(abs(stroke.a - 1.0) < tolerance)
    }
}

// MARK: - Token Adaptation Notes

/// These pins guard against accidental local edits to the hand-mirrored
/// eiDotter tokens in `Library/DesignSystem/AmberTheme.swift`.
///
/// **Token source:** eiDotter (github.com/CinimoDY/eiDotter)
/// **Workflow:** PORT/SKIP/EVALUATE → mirror into `AmberTheme.swift` →
/// update the drift-guard expected values above.
///
/// **Scope:** This is a *local pin* that catches local edits. True
/// upstream-divergence detection (if eiDotter's published values change)
/// will migrate to DMNC-801's generated tokens. Until then, this guard
/// assumes the current code values are the baseline truth and fails if
/// they drift locally without intention.
///
/// **Computed-blend tokens (out of scope):**
/// `glucoseLowBuffer`, `glucoseRising`, `glucoseHighBuffer` are derived
/// via RGB interpolation, not pinned. Changes to the three RGB base vectors
/// (greenRGB, amberRGB, redRGB) will change the blends; this is intentional.
