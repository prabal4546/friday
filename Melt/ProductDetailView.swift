import RealityKit
import SwiftUI

struct ProductDetailView: View {
    @EnvironmentObject private var store: MeltStore
    let productId: String

    var body: some View {
        if let product = store.product(id: productId) {
            List {
                Section {
                    ModelPreview(product: product)
                        .frame(height: 300)
                        .listRowInsets(EdgeInsets())
                }
                Section {
                    LabeledContent("Creator", value: product.creatorName)
                    LabeledContent("Price", value: dollars(product.priceCents))
                    LabeledContent("Filament", value: product.filament.label)
                    LabeledContent("Status", value: product.status.label)
                    LabeledContent("Sold", value: "\(product.salesCount)")
                }
                if let printNote = product.printNote {
                    Section("Printability") {
                        Label(printNote, systemImage: "exclamationmark.triangle")
                    }
                }
                Section("Prompt") {
                    Text(product.prompt)
                }
            }
            .navigationTitle(product.name)
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("This product is gone", systemImage: "questionmark.circle")
        }
    }
}

struct ModelPreview: View {
    let product: Product

    var body: some View {
        switch product.status {
        case .generating:
            ProgressView("Generating the model")
                .frame(maxWidth: .infinity)
        case .failed:
            ContentUnavailableView(
                "No model",
                systemImage: "cube.transparent",
                description: Text(product.failureReason ?? "Generation failed")
            )
        case .ready, .published:
            RealityView { content in
                content.camera = .virtual
                content.add(fixtureModel(for: product))
                let light = DirectionalLight()
                light.light.intensity = 2500
                light.look(at: .zero, from: [1, 2, 2], relativeTo: nil)
                content.add(light)
            }
            .realityViewCameraControls(.orbit)
            .accessibilityLabel("3D preview of \(product.name)")
        }
    }
}

@MainActor
private func fixtureModel(for product: Product) -> Entity {
    let material = SimpleMaterial(color: UIColor(product.filament.color), roughness: 0.55, isMetallic: false)
    let root = Entity()
    func add(_ mesh: MeshResource, at position: SIMD3<Float>) {
        let part = ModelEntity(mesh: mesh, materials: [material])
        part.position = position
        root.addChild(part)
    }
    switch product.name.utf8.reduce(0, { $0 + Int($1) }) % 3 {
    case 0:
        add(.generateSphere(radius: 0.26), at: [0, -0.12, 0])
        add(.generateSphere(radius: 0.18), at: [0, 0.24, 0])
        add(.generateCone(height: 0.16, radius: 0.06), at: [-0.1, 0.45, 0])
        add(.generateCone(height: 0.16, radius: 0.06), at: [0.1, 0.45, 0])
    case 1:
        add(.generateCylinder(height: 0.5, radius: 0.22), at: [0, 0, 0])
        add(.generateCylinder(height: 0.05, radius: 0.27), at: [0, 0.27, 0])
        add(.generateCylinder(height: 0.05, radius: 0.18), at: [0, -0.27, 0])
    default:
        add(.generateBox(size: [0.5, 0.22, 0.5], cornerRadius: 0.04), at: [0, -0.13, 0])
        add(.generateBox(size: [0.42, 0.22, 0.42], cornerRadius: 0.04), at: [0, 0.11, 0])
    }
    return root
}
