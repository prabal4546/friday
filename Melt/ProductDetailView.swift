import Combine
import RealityKit
import SwiftUI

struct ProductDetailView: View {
    @EnvironmentObject private var store: MeltStore
    @Environment(\.openURL) private var openURL
    let productId: String
    @State private var errorMessage: String?
    @State private var commerceMessage: String?
    @State private var isWorking = false

    var body: some View {
        if let product = store.product(id: productId) {
            List {
                Section {
                    ModelPreview(product: product)
                        .frame(height: 300)
                        .listRowInsets(EdgeInsets())
                }
                if product.status == .ready, product.creatorId == store.profile?.id {
                    Section("Sell this design") {
                        LabeledContent("Storefront price", value: dollars(product.priceCents))
                        Button("Publish for \(dollars(product.priceCents))") {
                            isWorking = true
                            Task {
                                do {
                                    try await store.publish(productId: product.id, priceCents: product.priceCents)
                                    commerceMessage = "Published. This design is now in the Shop."
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                                isWorking = false
                            }
                        }
                        .disabled(isWorking)
                    }
                } else if product.status == .published, product.creatorId != store.profile?.id {
                    if !store.isFriend(profileId: product.creatorId) {
                        Section("Creator") {
                            Button("Connect with \(product.creatorName)") {
                                isWorking = true
                                Task {
                                    do {
                                        try await store.connect(profileId: product.creatorId)
                                        commerceMessage = "Connected. You can now challenge this creator."
                                    } catch {
                                        errorMessage = error.localizedDescription
                                    }
                                    isWorking = false
                                }
                            }
                            .disabled(isWorking)
                        }
                    }
                    Section("Order") {
                        Button("Buy for \(dollars(product.priceCents))") {
                            isWorking = true
                            Task {
                                do {
                                    if let checkout = try await store.checkout(productId: product.id) {
                                        openURL(checkout)
                                    } else {
                                        commerceMessage = "Demo payment complete. Your order is now Paid."
                                    }
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                                isWorking = false
                            }
                        }
                        .disabled(isWorking)
                        if isWorking { ProgressView("Preparing checkout") }
                    }
                }
                if let commerceMessage {
                    Section {
                        Label(commerceMessage, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                if product.status == .ready, product.creatorId == store.profile?.id {
                    Section("Filament") {
                        FilamentPicker(
                            selection: Binding(
                                get: { product.filament },
                                set: { filament in
                                    Task {
                                        do {
                                            try await store.setFilament(filament, productId: product.id)
                                        } catch {
                                            errorMessage = error.localizedDescription
                                        }
                                    }
                                }
                            )
                        )
                    }
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
            .errorAlert("Couldn't complete that action", message: $errorMessage)
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
            ProgressView("Generating the model. This can take a few minutes.")
                .frame(maxWidth: .infinity)
        case .failed:
            ContentUnavailableView(
                "No model",
                systemImage: "cube.transparent",
                description: Text(product.failureReason ?? "Generation failed")
            )
        case .ready, .published:
            #if targetEnvironment(simulator)
            VStack(spacing: 12) {
                if let thumbnail = product.thumbnailURL {
                    AsyncImage(url: thumbnail) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Image(systemName: "cube.transparent").font(.largeTitle)
                    }
                } else {
                    Image(systemName: "cube.transparent").font(.largeTitle)
                }
                Text("3D preview unavailable in this simulator. Open on an iPhone to rotate the model.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity)
            #else
            ModelStage(product: product)
            #endif
        }
    }
}

private struct ModelStage: View {
    let product: Product
    @State private var pivot = Entity()
    @State private var note: String?
    @State private var isLoading = false
    @State private var isSpinning = true
    private let frames = Timer.publish(every: 1.0 / 30, on: .main, in: .common).autoconnect()

    var body: some View {
        RealityView { content in
            content.camera = .virtual
            content.add(pivot)
            let light = DirectionalLight()
            light.light.intensity = 2500
            light.look(at: .zero, from: [1, 2, 2], relativeTo: nil)
            content.add(light)
        }
        .realityViewCameraControls(.orbit)
        .accessibilityLabel("3D preview of \(product.name)")
        .overlay {
            if isLoading {
                ProgressView("Loading the model")
            }
        }
        .overlay(alignment: .bottom) {
            HStack {
                if let note {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(isSpinning ? "Pause" : "Spin", systemImage: isSpinning ? "pause.fill" : "arrow.triangle.2.circlepath") {
                    isSpinning.toggle()
                }
                .buttonStyle(.bordered)
            }
            .padding(12)
        }
        .task(id: product.usdzURL) {
            await showModel()
        }
        .onChange(of: product.filament) {
            applyFilament(product.filament, to: pivot)
        }
        .onReceive(frames) { _ in
            if isSpinning {
                pivot.transform.rotation *= simd_quatf(angle: .pi / 180, axis: [0, 1, 0])
            }
        }
    }

    private func showModel() async {
        var model = fixtureModel(for: product)
        note = "Stand-in shape"
        if let remote = product.usdzURL {
            isLoading = true
            do {
                let file = try await cachedModelFile(for: remote, productId: product.id)
                do {
                    model = try await Entity(contentsOf: file)
                    note = nil
                } catch {
                    try? FileManager.default.removeItem(at: file)
                    throw error
                }
            } catch {
                note = "The model couldn't be loaded. Showing a stand-in shape."
            }
            isLoading = false
        }
        let bounds = model.visualBounds(relativeTo: nil)
        let scale = 1.1 / max(bounds.extents.x, bounds.extents.y, bounds.extents.z, .leastNonzeroMagnitude)
        let fitted = Entity()
        fitted.addChild(model)
        fitted.scale = SIMD3(repeating: scale)
        fitted.position = -bounds.center * scale
        pivot.children.removeAll()
        pivot.addChild(fitted)
        applyFilament(product.filament, to: pivot)
    }
}

private func cachedModelFile(for remote: URL, productId: String) async throws -> URL {
    let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("models", isDirectory: true)
    let file = folder.appendingPathComponent(productId).appendingPathExtension("usdz")
    if FileManager.default.fileExists(atPath: file.path) { return file }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let (downloaded, response) = try await URLSession.shared.download(from: remote)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
        throw MeltError("The model file couldn't be downloaded")
    }
    try FileManager.default.moveItem(at: downloaded, to: file)
    return file
}

@MainActor
private func applyFilament(_ filament: Filament, to entity: Entity) {
    if var model = entity.components[ModelComponent.self] {
        let material = SimpleMaterial(color: UIColor(filament.color), roughness: 0.55, isMetallic: false)
        model.materials = model.materials.map { _ in material }
        entity.components.set(model)
    }
    for child in entity.children {
        applyFilament(filament, to: child)
    }
}

@MainActor
private func fixtureModel(for product: Product) -> Entity {
    let root = Entity()
    func add(_ mesh: MeshResource, at position: SIMD3<Float>) {
        let part = ModelEntity(mesh: mesh, materials: [SimpleMaterial()])
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
