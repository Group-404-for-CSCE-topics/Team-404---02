//
//  render-app-icon.swift
//  MercyDrones — draws the app icon and writes it into the asset catalog.
//
//  Run from the repo root:
//      swift Tools/render-app-icon.swift
//
//  Output is a 1024×1024 opaque PNG (iOS masks the corners itself).
//  Colors match Theme.blue / Theme.green (light) in UI.swift.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

let canvas: CGFloat = 1024
let outputPath = CommandLine.arguments.dropFirst().first
    ?? "Assets.xcassets/AppIcon.appiconset/AppIcon.png"

let blue  = Color(red: 0x1F / 255, green: 0x6F / 255, blue: 0xEB / 255)
let green = Color(red: 0x15 / 255, green: 0x92 / 255, blue: 0x4A / 255)
let brand = LinearGradient(colors: [blue, green], startPoint: .topLeading, endPoint: .bottomTrailing)

// MARK: - Icon

struct AppIcon: View {
    var body: some View {
        ZStack {
            Rectangle().fill(brand)
            RadialGradient(colors: [.white.opacity(0.18), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 900)
            Quadcopter()
        }
        .frame(width: canvas, height: canvas)
    }
}

/// Top-down quadcopter: X-frame arms, four rotor discs, a body carrying a medical cross.
struct Quadcopter: View {
    let rotorOffset: CGFloat = 250
    let rotorRadius: CGFloat = 150

    var body: some View {
        ZStack {
            ForEach([45.0, -45.0], id: \.self) { angle in
                Capsule()
                    .fill(.white)
                    .frame(width: rotorOffset * 2 * sqrt(2), height: 64)
                    .rotationEffect(.degrees(angle))
            }

            ForEach(0..<4, id: \.self) { corner in
                Rotor(radius: rotorRadius)
                    .offset(x: corner % 2 == 0 ? -rotorOffset : rotorOffset,
                            y: corner < 2 ? -rotorOffset : rotorOffset)
            }

            Circle()
                .fill(.white)
                .frame(width: 340, height: 340)
                .shadow(color: .black.opacity(0.18), radius: 24, y: 10)

            MedicalCross()
                .fill(brand)
                .frame(width: 190, height: 190)
        }
    }
}

struct Rotor: View {
    let radius: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(.white.opacity(0.22))
            Circle().strokeBorder(.white, lineWidth: 36)
            Circle().fill(.white).frame(width: 104, height: 104)
        }
        .frame(width: radius * 2, height: radius * 2)
    }
}

struct MedicalCross: Shape {
    func path(in rect: CGRect) -> Path {
        let bar = rect.width * 0.34
        let corner = CGSize(width: bar * 0.25, height: bar * 0.25)
        var path = Path()
        path.addRoundedRect(in: CGRect(x: rect.minX, y: rect.midY - bar / 2, width: rect.width, height: bar),
                            cornerSize: corner)
        path.addRoundedRect(in: CGRect(x: rect.midX - bar / 2, y: rect.minY, width: bar, height: rect.height),
                            cornerSize: corner)
        return path
    }
}

// MARK: - Render

MainActor.assumeIsolated {
    let renderer = ImageRenderer(content: AppIcon())
    renderer.scale = 1
    guard let rendered = renderer.cgImage else { fatalError("Could not render the icon") }

    // App icons must not have an alpha channel, so redraw onto an opaque context.
    let width = Int(canvas), height = Int(canvas)
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        fatalError("Could not create the bitmap context")
    }
    context.draw(rendered, in: CGRect(x: 0, y: 0, width: width, height: height))

    let url = URL(fileURLWithPath: outputPath)
    guard let opaque = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("Could not prepare \(url.path)")
    }
    CGImageDestinationAddImage(destination, opaque, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Could not write \(url.path)") }
    print("Wrote \(url.path)")
}
