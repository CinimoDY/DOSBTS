//
//  DOSScanlineOverlay.swift
//  DOSBTS
//
//  CRT scanline effect overlay for DOS aesthetic
//

import SwiftUI

struct DOSScanlineOverlay: View {
    private let lineSpacing: CGFloat = 3
    private let lineOpacity: Double = 0.04

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let lineCount = Int(size.height / lineSpacing)
                for i in 0..<lineCount {
                    let y = CGFloat(i) * lineSpacing
                    let rect = CGRect(x: 0, y: y, width: size.width, height: 1)
                    context.fill(Path(rect), with: .color(.black.opacity(lineOpacity)))
                }
            }
        }
        .ignoresSafeArea()
    }
}
