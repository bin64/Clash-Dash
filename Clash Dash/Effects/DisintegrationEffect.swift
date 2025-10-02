//
//  DisintegrationEffect.swift
//  Clash Dash
//
//  Created by Balaji Venkatesh on 21/11/24.
//

import SwiftUI

extension View {
    @ViewBuilder
    func disintegrationEffect(isDeleted: Bool, completion: @escaping () -> ()) -> some View {
        self
            .modifier(DisintegrationEffectModifier(isDeleted: isDeleted, completion: completion))
    }
}

fileprivate struct DisintegrationEffectModifier: ViewModifier {
    var isDeleted: Bool
    var completion: () -> ()
    /// View Properties
    @State private var particles: [SnapParticle] = []
    @State private var animateEffect: Bool = false
    @State private var triggerSnapshot: Bool = false
    @State private var isDeleteCompleted: Bool = false
    func body(content: Content) -> some View {
        content
            .opacity(particles.isEmpty && !isDeleteCompleted ? 1 : 0)
            .overlay(alignment: .topLeading) {
                DisintegrationEffectView(particles: $particles, animateEffect: $animateEffect)
            }
            .snapshot(trigger: triggerSnapshot) { snapshot in
                Task.detached(priority: .high) {
                    /// If you want to prevent the button from being stuck, you can set the tapGesture to 0 instead of 0.2.
                    //try? await Task.sleep(for: .seconds(0.2))
                    try? await Task.sleep(for: .seconds(0))
                    await createParticles(snapshot)
                }
            }
            .onChange(of: isDeleted) { newValue in
                if newValue && particles.isEmpty {
                    triggerSnapshot = true
                }
            }
    }

    private func createParticles(_ snapshot: UIImage) async {
        var particles: [SnapParticle] = []
        let size = snapshot.size
        let width = size.width
        let height = size.height
        let maxGridCount: Int = 2000

        var gridSize: Int = 1
        var rows = Int(height) / gridSize
        var columns = Int(width) / gridSize

        while (rows * columns) >= maxGridCount {
            gridSize += 1
            rows = Int(height) / gridSize
            columns = Int(width) / gridSize
        }

        print("Grid Created:", rows * columns)

        for row in 0...rows {
            for column in 0...columns {
                let positionX = column * gridSize
                let positionY = row * gridSize

                let cropRect = CGRect(x: positionX, y: positionY, width: gridSize, height: gridSize)
                let croppedImage = cropImage(snapshot, rect: cropRect)
                particles.append(.init(
                    particleImage: croppedImage,
                    particleOffset: .init(width: positionX, height: positionY)
                ))
            }
        }

        await MainActor.run { [particles] in
            self.particles = particles
            /// Animating
            withAnimation(.easeInOut(duration: 1.5)) {
                animateEffect = true
            }
            // Use DispatchQueue for completion callback after animation duration
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                isDeleteCompleted = true
                self.particles = []
                completion()
            }
        }
    }

    private func cropImage(_ snapshot: UIImage, rect: CGRect) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: rect.size, format: format)
        return renderer.image { ctx in
            ctx.cgContext.interpolationQuality = .low
            snapshot.draw(at: .init(x: -rect.origin.x, y: -rect.origin.y))
        }
    }
}

fileprivate struct DisintegrationEffectView: View {
    @Binding var particles: [SnapParticle]
    @Binding var animateEffect: Bool
    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(particles) { particle in
                Image(uiImage: particle.particleImage)
                    .offset(particle.particleOffset)
                    .offset(
                        x: animateEffect ? .random(in: -60...(-10)) : 0,
                        y: animateEffect ? .random(in: -100...(-10)) : 0
                    )
                    .opacity(animateEffect ? 0 : 1)
            }
        }
        .compositingGroup()
        .blur(radius: animateEffect ? 5 : 0)
    }
}

fileprivate struct SnapParticle: Identifiable {
    var id: String = UUID().uuidString
    var particleImage: UIImage
    var particleOffset: CGSize
}
