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
