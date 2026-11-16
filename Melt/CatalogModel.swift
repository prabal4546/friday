import RealityKit
import UIKit

/// Bundled preview geometry. Keys are explicit backend identifiers, never product-name guesses.
@MainActor enum CatalogModel {
    static func make(key: String) throws -> Entity {
        let root = Entity()
        let dark = UIColor(white: 0.10, alpha: 1)
        let cream = UIColor(red: 0.98, green: 0.92, blue: 0.79, alpha: 1)
        @discardableResult
        func part(_ mesh: MeshResource, at position: SIMD3<Float> = .zero,
                  scale: SIMD3<Float> = [1, 1, 1], color: UIColor? = nil) -> ModelEntity {
            let entity = ModelEntity(mesh: mesh, materials: [SimpleMaterial(color: color ?? .white, roughness: 0.7, isMetallic: false)])
            entity.position = position
            entity.scale = scale
            if color != nil { entity.name = "fixed-catalog-detail" }
            root.addChild(entity)
            return entity
        }
        @discardableResult
        func ball(_ radius: Float, _ position: SIMD3<Float>, _ scale: SIMD3<Float> = [1, 1, 1], _ color: UIColor? = nil) -> ModelEntity {
            part(.generateSphere(radius: radius), at: position, scale: scale, color: color)
        }
        func eyes(y: Float, z: Float, spacing: Float, sleepy: Bool = false) {
            for x in [-spacing, spacing] {
                ball(0.025, [x, y, z], [1, sleepy ? 0.25 : 1.3, 0.55], dark)
            }
        }

        switch key {
        case "twisted-hex-vase":
            var profile: [SIMD2<Float>] = [[0, 0], [0.28, 0]]
            for i in 1...20 {
                let y = Float(i) * 0.038
                profile.append([0.28 - 0.05 * sin(y / 0.76 * .pi), y])
            }
            profile.append([0.235, 0.76])
            for i in stride(from: 19, through: 1, by: -1) {
                let y = Float(i) * 0.038
                profile.append([0.235 - 0.05 * sin(y / 0.76 * .pi), y])
            }
            profile.append([0, 0.038])
            part(try surface(profile, sides: 6, twist: 0.85))

        case "capybara-planter":
            // Hollow oval body with a broad muzzle, tiny ears, and four short legs.
            part(try surface([[0, 0], [0.21, 0], [0.32, 0.12], [0.33, 0.27],
                              [0.28, 0.34], [0.235, 0.34], [0.28, 0.25], [0.26, 0.12], [0, 0.06]]),
                 at: [0, 0.13, -0.10], scale: [1, 1, 1.35])
            ball(0.23, [0, 0.37, 0.36], [1, 0.9, 1.25])
            part(.generateBox(size: [0.36, 0.22, 0.28], cornerRadius: 0.09), at: [0, 0.32, 0.55])
            for x: Float in [-0.15, 0.15] {
                ball(0.07, [x, 0.55, 0.32], [0.8, 1, 0.6])
                for z: Float in [-0.32, 0.17] { ball(0.105, [x, 0.09, z], [0.8, 1, 1]) }
            }
            eyes(y: 0.42, z: 0.609, spacing: 0.12, sleepy: true)
            for x: Float in [-0.065, 0.065] { ball(0.012, [x, 0.34, 0.693], [1, 0.65, 0.5], dark) }

        case "ghost-night-light":
            // A continuous skirt with a scalloped hem, tapering into a rounded dome.
            part(try surface([[0, 0.045], [0.32, 0.045], [0.34, 0.10], [0.29, 0.22],
                              [0.255, 0.40], [0.25, 0.55], [0.21, 0.68], [0.12, 0.76], [0, 0.79]], wave: 0.035))
            eyes(y: 0.52, z: 0.249, spacing: 0.085)
            ball(0.045, [0, 0.405, 0.263], [0.7, 1.1, 0.25], dark)
            for x: Float in [-0.28, 0.28] {
                let arm = ball(0.095, [x, 0.38, 0], [1, 1.7, 0.8])
                arm.orientation = simd_quatf(angle: x > 0 ? -.pi / 4 : .pi / 4, axis: [0, 0, 1])
            }

        case "fox-desk-buddy":
            ball(0.23, [0, 0.24, 0], [0.85, 1.15, 0.8])
            ball(0.16, [0, 0.25, 0.14], [0.7, 1.1, 0.3], cream)
            ball(0.23, [0, 0.59, 0.02], [1, 0.9, 0.8])
            for x: Float in [-0.14, 0.14] {
                part(.generateCone(height: 0.25, radius: 0.09), at: [x, 0.82, 0.015], scale: [1, 1, 0.6])
                part(.generateCone(height: 0.14, radius: 0.045), at: [x, 0.82, 0.06], scale: [1, 1, 0.4], color: cream)
                ball(0.08, [x * 0.7, 0.065, 0.11], [1, 0.75, 1.5])
                // Forward paws form a small cradle for earbuds.
                ball(0.075, [x, 0.29, 0.21], [0.7, 0.8, 1.5])
                ball(0.10, [x * 0.6, 0.535, 0.18], [1, 0.7, 0.55], cream)
            }
            eyes(y: 0.625, z: 0.197, spacing: 0.085)
            ball(0.034, [0, 0.545, 0.235], [1, 0.7, 0.8], dark)
            let tail = ball(0.16, [0.29, 0.28, -0.08], [0.9, 1.9, 0.85])
            tail.orientation = simd_quatf(angle: -.pi / 5, axis: [0, 0, 1])
            let tip = ball(0.10, [0.42, 0.48, -0.08], [0.9, 1.3, 0.9], cream)
            tip.orientation = tail.orientation

        case "top-hat-duck":
            ball(0.27, [0, 0.25, -0.06], [1, 0.85, 1.25])
            ball(0.19, [0, 0.54, 0.17])
            ball(0.13, [0, 0.49, 0.36], [1, 0.35, 1.1], .systemOrange)
            eyes(y: 0.57, z: 0.337, spacing: 0.085)
            for x: Float in [-0.24, 0.24] {
                ball(0.13, [x, 0.29, -0.075], [0.35, 0.8, 1.7])
                ball(0.09, [x * 0.5, 0.055, 0.08], [1, 0.35, 1.5], .systemOrange)
            }
            part(.generateCylinder(height: 0.035, radius: 0.24), at: [0, 0.705, 0.17], color: dark)
            part(.generateCylinder(height: 0.22, radius: 0.155), at: [0, 0.825, 0.17], color: dark)
            part(.generateCylinder(height: 0.045, radius: 0.158), at: [0, 0.747, 0.17], color: .systemRed)

        case "hex-bins":
            let mesh = try surface([[0, 0], [0.32, 0], [0.36, 0.29], [0.36, 0.33],
                                    [0.31, 0.33], [0.275, 0.05], [0, 0.05]], sides: 6)
            part(mesh, at: [-0.12, 0, 0.06])
            part(mesh, at: [0.08, 0.34, -0.09])

        case "egg-cup":
            part(.generateCylinder(height: 0.055, radius: 0.28), at: [0, 0.028, 0])
            part(.generateCylinder(height: 0.18, radius: 0.07), at: [0, 0.14, 0])
            part(try surface([[0, 0], [0.09, 0], [0.16, 0.08], [0.23, 0.21], [0.25, 0.32],
                              [0.215, 0.32], [0.195, 0.22], [0.12, 0.10], [0, 0.045]]), at: [0, 0.20, 0])

        default:
            throw MeltError("Unknown catalog model")
        }
        return root
    }

    /// Revolve a closed radial cross-section, including inner walls and floor.
    /// Low side counts produce polygonal vessels; the profile remains open at the rim.
    private static func surface(_ profile: [SIMD2<Float>], sides: Int = 64,
                                twist: Float = 0, wave: Float = 0) throws -> MeshResource {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for point in profile {
            for side in 0..<sides {
                let angle = Float(side) * 2 * .pi / Float(sides) + point.y * twist
                let hem = wave * cos(angle * 7) * max(0, 1 - point.y / 0.22)
                positions.append([point.x * cos(angle), point.y + hem, point.x * sin(angle)])
                normals.append(.zero)
            }
        }
        for ring in 0..<profile.count {
            let next = (ring + 1) % profile.count
            for side in 0..<sides {
                let following = (side + 1) % sides
                let a = ring * sides + side, b = ring * sides + following
                let c = next * sides + following, d = next * sides + side
                for triangle in [[a, c, b], [a, d, c]] {
                    let normal = cross(positions[triangle[1]] - positions[triangle[0]], positions[triangle[2]] - positions[triangle[0]])
                    for index in triangle { normals[index] += normal; indices.append(UInt32(index)) }
                }
            }
        }
        normals = normals.map { length_squared($0) > 0.0000001 ? normalize($0) : SIMD3<Float>(0, 1, 0) }
        var descriptor = MeshDescriptor(name: "Catalog vessel")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }
}
