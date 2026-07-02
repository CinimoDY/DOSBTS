//
//  ItemBarcodeScannerView.swift
//  DOSBTS
//
//  Lightweight callback-based barcode scanner for replacing individual items
//  on the staging plate. Does NOT use Redux state — returns NutritionEstimate
//  directly via callback to avoid foodAnalysisResult collision.

import AVFoundation
import SwiftUI

struct ItemBarcodeScannerView: View {
    var onResult: (NutritionEstimate) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var hasScanned = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            if isLoading {
                VStack(spacing: DOSSpacing.md) {
                    FiguresLoadingView.inline
                    Text("Looking up product...")
                        .font(DOSTypography.body)
                        .foregroundStyle(AmberTheme.amber)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            } else if let error = errorMessage {
                DOSErrorState(message: error) {
                    hasScanned = false
                    errorMessage = nil
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            } else {
                ZStack {
                    Color.black.edgesIgnoringSafeArea(.all)
                    #if targetEnvironment(simulator)
                    simulatorFallback
                    #else
                    ScannerVC_Wrapper(onScan: handleScan)
                        .edgesIgnoringSafeArea(.all)

                    viewfinderOverlay
                    #endif
                }
            }
        }
        .dosNavigationTitle("Scan Item")
        // Pushed onto the food-entry NavigationStack: suppress the system back
        // button so Cancel is the sole leading control. interactiveDismissDisabled
        // keeps a swipe-down from tearing down the Log Meal sheet (and losing the
        // staged meal) while replacing an item.
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled()
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(AmberTheme.amber)
            }
        }
    }

    #if !targetEnvironment(simulator)
    private var viewfinderOverlay: some View {
        VStack {
            Spacer()
            Rectangle()
                .stroke(AmberTheme.amber, lineWidth: 2)
                .frame(width: 280, height: 120)
            Text("Scan barcode to replace item")
                .font(DOSTypography.caption)
                .foregroundStyle(AmberTheme.amber)
                .padding(.top, DOSSpacing.sm)
            Spacer()
            Spacer()
        }
    }
    #endif

    private func handleScan(_ code: String) {
        guard !hasScanned else { return }
        hasScanned = true
        isLoading = true

        // Call OFF directly — no Redux dispatch
        Task {
            do {
                let estimate = try await lookupBarcodeInOpenFoodFacts(code)
                await MainActor.run {
                    onResult(estimate)
                }
                // Allow SwiftUI to process the state update before popping
                try? await Task.sleep(nanoseconds: 50_000_000) // ~3 frames
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "Product not found. Try again or cancel."
                    hasScanned = false
                }
            }
        }
    }

    #if targetEnvironment(simulator)
    @State private var manualBarcode = ""

    private var simulatorFallback: some View {
        VStack(spacing: DOSSpacing.md) {
            // Icon centered inside the framing box (mirrors the on-device viewfinder).
            ZStack {
                Rectangle()
                    .stroke(AmberTheme.amber, lineWidth: 2)
                    .frame(width: 280, height: 120)

                Image(systemName: "barcode.viewfinder")
                    .font(DOSTypography.mono(size: 64))
                    .foregroundStyle(AmberTheme.amber)
            }
            Text("Camera unavailable in simulator")
                .font(DOSTypography.body)
                .foregroundStyle(AmberTheme.amber)
            TextField("Enter barcode", text: $manualBarcode)
                .font(DOSTypography.body)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 250)
            Button("Look Up") {
                let trimmed = manualBarcode.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                handleScan(trimmed)
            }
            .foregroundStyle(AmberTheme.amber)
        }
    }
    #endif
}
