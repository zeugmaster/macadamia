//
//  MeshBackground.swift
//  macadamia
//
//  Created by zm on 09.02.26.
//

import SwiftUI

struct MeshBackground: View {
    private static let meshWidth = 6
    private static let meshHeight = 4
    private static let animationPhases = [0, 1, 2, 3, 4]

    private static let keyframes: [[SIMD2<Float>]] = [
        // State 0
        [
            SIMD2<Float>(0.0, 0.0),
            SIMD2<Float>(0.2, 0.0),
            SIMD2<Float>(0.4, 0.0),
            SIMD2<Float>(0.6, 0.0),
            SIMD2<Float>(0.8, 0.0),
            SIMD2<Float>(1.0, 0.0),
            SIMD2<Float>(0.00015911508, 0.5450742),
            SIMD2<Float>(0.27456862, 0.48900932),
            SIMD2<Float>(0.467743, 0.37833688),
            SIMD2<Float>(0.627137, 0.49174696),
            SIMD2<Float>(0.872748, 0.541055),
            SIMD2<Float>(1.0, 0.5915908),
            SIMD2<Float>(0.0, 0.8132732),
            SIMD2<Float>(0.16844758, 0.5889521),
            SIMD2<Float>(0.39227474, 0.7834711),
            SIMD2<Float>(0.6343452, 0.7475437),
            SIMD2<Float>(0.7867804, 0.59123605),
            SIMD2<Float>(1.0, 0.6666667),
            SIMD2<Float>(0.0, 1.0),
            SIMD2<Float>(0.2, 1.0),
            SIMD2<Float>(0.4, 1.0),
            SIMD2<Float>(0.6, 1.0),
            SIMD2<Float>(0.8, 1.0),
            SIMD2<Float>(1.0, 1.0),
        ],
        // State 1
        [
            SIMD2<Float>(0.0, 0.0),
            SIMD2<Float>(0.2, 0.0),
            SIMD2<Float>(0.4, 0.0),
            SIMD2<Float>(0.6, 0.0),
            SIMD2<Float>(0.8, 0.0),
            SIMD2<Float>(1.0, 0.0),
            SIMD2<Float>(0.00015911508, 0.5450742),
            SIMD2<Float>(0.27456862, 0.48900932),
            SIMD2<Float>(0.4717206, 0.6098951),
            SIMD2<Float>(0.627137, 0.49174696),
            SIMD2<Float>(0.8801866, 0.49561995),
            SIMD2<Float>(1.0, 0.5915908),
            SIMD2<Float>(0.0, 0.8132732),
            SIMD2<Float>(0.17216304, 0.628887),
            SIMD2<Float>(0.41285598, 0.6301401),
            SIMD2<Float>(0.5971366, 0.73958),
            SIMD2<Float>(0.72482294, 0.60411584),
            SIMD2<Float>(0.9995068, 0.7576629),
            SIMD2<Float>(0.0, 1.0),
            SIMD2<Float>(0.2, 1.0),
            SIMD2<Float>(0.4, 1.0),
            SIMD2<Float>(0.6, 1.0),
            SIMD2<Float>(0.8, 1.0),
            SIMD2<Float>(1.0, 1.0),
        ],
        // State 2
        [
            SIMD2<Float>(0.0, 0.0),
            SIMD2<Float>(0.2, 0.0),
            SIMD2<Float>(0.4, 0.0),
            SIMD2<Float>(0.6, 0.0),
            SIMD2<Float>(0.8, 0.0),
            SIMD2<Float>(1.0, 0.0),
            SIMD2<Float>(0.00015911508, 0.5450742),
            SIMD2<Float>(0.19762084, 0.42716947),
            SIMD2<Float>(0.48486325, 0.52587473),
            SIMD2<Float>(0.65117913, 0.28321138),
            SIMD2<Float>(0.8801866, 0.49561995),
            SIMD2<Float>(1.0, 0.5915908),
            SIMD2<Float>(0.0, 0.8132732),
            SIMD2<Float>(0.16478805, 0.7524697),
            SIMD2<Float>(0.37010148, 0.8439218),
            SIMD2<Float>(0.6079167, 0.8253579),
            SIMD2<Float>(0.72482294, 0.60411584),
            SIMD2<Float>(0.9995068, 0.7576629),
            SIMD2<Float>(0.0, 1.0),
            SIMD2<Float>(0.2, 1.0),
            SIMD2<Float>(0.4, 1.0),
            SIMD2<Float>(0.6, 1.0),
            SIMD2<Float>(0.8, 1.0),
            SIMD2<Float>(1.0, 1.0),
        ],
        // State 3
        [
            SIMD2<Float>(0.0, 0.0),
            SIMD2<Float>(0.2, 0.0),
            SIMD2<Float>(0.4, 0.0),
            SIMD2<Float>(0.6, 0.0),
            SIMD2<Float>(0.8, 0.0),
            SIMD2<Float>(1.0, 0.0),
            SIMD2<Float>(0.0, 0.34209988),
            SIMD2<Float>(0.19762084, 0.42716947),
            SIMD2<Float>(0.56822354, 0.5882373),
            SIMD2<Float>(0.6834953, 0.3770809),
            SIMD2<Float>(0.8801866, 0.49561995),
            SIMD2<Float>(1.0, 0.5915908),
            SIMD2<Float>(0.0, 0.7506218),
            SIMD2<Float>(0.19225118, 0.52416444),
            SIMD2<Float>(0.39682457, 0.6942192),
            SIMD2<Float>(0.59450346, 0.70552146),
            SIMD2<Float>(0.72482294, 0.60411584),
            SIMD2<Float>(0.9995068, 0.7576629),
            SIMD2<Float>(0.0, 1.0),
            SIMD2<Float>(0.1547955, 1.0),
            SIMD2<Float>(0.3388207, 1.0),
            SIMD2<Float>(0.6229127, 1.0),
            SIMD2<Float>(0.8, 1.0),
            SIMD2<Float>(1.0, 1.0),
        ],
        // State 4
        [
            SIMD2<Float>(0.0, 0.0),
            SIMD2<Float>(0.2, 0.0),
            SIMD2<Float>(0.4, 0.0),
            SIMD2<Float>(0.6, 0.0),
            SIMD2<Float>(0.8, 0.0),
            SIMD2<Float>(1.0, 0.0),
            SIMD2<Float>(0.0, 0.34209988),
            SIMD2<Float>(0.19762084, 0.42716947),
            SIMD2<Float>(0.50192106, 0.5842833),
            SIMD2<Float>(0.8628347, 0.43352634),
            SIMD2<Float>(0.9215009, 0.6573591),
            SIMD2<Float>(1.0, 0.5915908),
            SIMD2<Float>(0.0, 0.7506218),
            SIMD2<Float>(0.19225118, 0.52416444),
            SIMD2<Float>(0.296089, 0.5917811),
            SIMD2<Float>(0.59450346, 0.70552146),
            SIMD2<Float>(0.72482294, 0.60411584),
            SIMD2<Float>(0.9995068, 0.7576629),
            SIMD2<Float>(0.0, 1.0),
            SIMD2<Float>(0.1547955, 1.0),
            SIMD2<Float>(0.3388207, 1.0),
            SIMD2<Float>(0.6229127, 1.0),
            SIMD2<Float>(0.8, 1.0),
            SIMD2<Float>(1.0, 1.0),
        ],
    ]

    private static let colors: [Color] = [
        Color(red: 0.091, green: 0.090, blue: 0.093),
        Color(red: 0.091, green: 0.090, blue: 0.093),
        Color(red: 0.091, green: 0.090, blue: 0.093),
        Color(red: 0.091, green: 0.090, blue: 0.093),
        Color(red: 0.091, green: 0.090, blue: 0.093),
        Color(red: 0.091, green: 0.090, blue: 0.093),
        Color(red: 0.139, green: 0.138, blue: 0.143),
        Color(red: 0.139, green: 0.138, blue: 0.143),
        Color(red: 0.139, green: 0.138, blue: 0.143),
        Color(red: 0.139, green: 0.138, blue: 0.143),
        Color(red: 0.139, green: 0.138, blue: 0.143),
        Color(red: 0.139, green: 0.138, blue: 0.143),
        Color(red: 0.031, green: 0.031, blue: 0.032),
        Color(red: 0.031, green: 0.031, blue: 0.032),
        Color(red: 0.031, green: 0.031, blue: 0.032),
        Color(red: 0.031, green: 0.031, blue: 0.032),
        Color(red: 0.031, green: 0.031, blue: 0.032),
        Color(red: 0.031, green: 0.031, blue: 0.032),
        Color(red: 0.068, green: 0.068, blue: 0.070),
        Color(red: 0.068, green: 0.068, blue: 0.070),
        Color(red: 0.068, green: 0.068, blue: 0.070),
        Color(red: 0.068, green: 0.068, blue: 0.070),
        Color(red: 0.068, green: 0.068, blue: 0.070),
        Color(red: 0.068, green: 0.068, blue: 0.070),
    ]

    var body: some View {
        GeometryReader { geo in
            let side = geo.size.height
            if #available(iOS 18.0, *) {
                PhaseAnimator(Self.animationPhases) { phase in
                    MeshGradient(
                        width: Self.meshWidth,
                        height: Self.meshHeight,
                        points: Self.keyframes[phase],
                        colors: Self.colors,
                        background: Color(red: 1, green: 1, blue: 1),
                        smoothsColors: true,
                        colorSpace: .device
                    )
                    .frame(width: side, height: side)
                } animation: { _ in
                    .linear(duration: 4.0)
                }
            } else {
                ZStack {
                    RadialGradient(
                        gradient: Gradient(colors: [Color(white: 0.1), .black]),
                        center: .leading,
                        startRadius: 100,
                        endRadius: 1000
                    )
                    RadialGradient(
                        gradient: Gradient(colors: [Color(white: 0.08), .clear]),
                        center: .bottomTrailing,
                        startRadius: 100,
                        endRadius: 400
                    )
                }
                .frame(width: side, height: side)
                .background(Color.gray.opacity(0.15))
            }
        }
        .ignoresSafeArea()
    }
}

#Preview {
    MeshBackground()
}
