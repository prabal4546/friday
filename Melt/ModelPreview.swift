import RealityKit
import SwiftUI

struct ModelPreview: View {
    let product: Product
    var compact = false

    var body: some View {
        if product.status == .ready || product.status == .published || (product.status == .generating && product.usdzURL != nil) {
            ModelStage(product: product, compact: compact)
                .overlay(alignment: .bottomLeading) {
                    if product.status == .generating, !compact {
                        GenerationProgress(product: product).padding(8).background(Studio.paper.opacity(0.94), in: Capsule())
                    }
                }
        } else if product.status == .generating {
            GenerationProgress(product: product, compact: compact)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "cube.transparent").font(.largeTitle)
                if !compact { Text(product.failureReason ?? "Generation failed").font(.subheadline).multilineTextAlignment(.center) }
            }.foregroundStyle(Studio.muted).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct GenerationProgress: View {
    let product: Product
    var compact = false
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                if !compact {
                    Text((product.generationStage ?? .generating).label)
                    if let start = product.generationRequestedAt {
                        let seconds = max(0, Int((product.generationFinishedAt ?? context.date).timeIntervalSince(start)))
                        Text(String(format: "%d:%02d", seconds / 60, seconds % 60)).monospacedDigit()
                    }
                }
            }.font(.caption).foregroundStyle(Studio.muted)
        }
    }
}

// Owns the original material slots separately so Original restores maps as well as tint.
@MainActor private final class PreviewScene: ObservableObject {
    let pivot = Entity()
    let camera = PerspectiveCamera()
    let ground = ModelEntity(mesh: .generatePlane(width: 200, depth: 200),
                             materials: [SimpleMaterial(color: UIColor(Studio.paper), roughness: 1, isMetallic: false)])
    var originals: [(Entity, ModelComponent)] = []
    var halfExtents = SIMD3<Float>(repeating: 0.575)
    var yaw: Float = 35 * .pi / 180
    var pitch: Float = 0
    var viewport = CGSize(width: 320, height: 235)
    var fittedDistance: Float = 0
    var loadedKey: String?

    func rememberMaterials(_ entity: Entity) {
        if var model = entity.components[ModelComponent.self] {
            // Meshy geometry-only USDZ has no material binding. RealityKit imports
            // that as an unnamed AnyMaterial (its magenta error shader), rather than
            // an empty array. Replace only that unbound placeholder or empty slots.
            // Authored PBR, unlit, shader-graph materials and their maps stay intact.
            let neutral = SimpleMaterial(color: UIColor(white: 0.72, alpha: 1), roughness: 0.65, isMetallic: false)
            if model.materials.isEmpty {
                model.materials = [neutral]
            } else {
                model.materials = model.materials.map { material in
                    if material.name == nil && String(describing: type(of: material)) == "AnyMaterial" {
                        return neutral
                    }
                    return material
                }
            }
            entity.components.set(model)
            originals.append((entity, model))
        }
        for child in entity.children { rememberMaterials(child) }
    }

    func appearance(for product: Product) {
        for (entity, model) in originals { entity.components.set(model) }
        if !product.hasOriginalAppearance || product.colorCustomized == true {
            applyFilament(product.filament, to: pivot)
        }
    }

    func pose(resetFit: Bool = false) {
        let orientation = simd_quatf(angle: pitch, axis: [1, 0, 0]) * simd_quatf(angle: yaw, axis: [0, 1, 0])
        pivot.orientation = orientation
        let elevation: Float = 15 * .pi / 180
        let forward = SIMD3<Float>(0, sin(elevation), cos(elevation))
        let up = SIMD3<Float>(0, cos(elevation), -sin(elevation))
        let tanY = tan(Float(34) * .pi / 360)
        let tanX = tanY * Float(max(viewport.width, 1) / max(viewport.height, 1))
        var distance: Float = 0
        var bottom: Float = 0
        // Project all eight rotated corners into the elevated camera's basis.
        // Include the end of the intro so that the short turn never crops the model.
        for yawOffset: Float in [0, 20 * .pi / 180] {
            let rotation = simd_quatf(angle: pitch, axis: [1, 0, 0]) * simd_quatf(angle: yaw + yawOffset, axis: [0, 1, 0])
            for x: Float in [-1, 1] { for y: Float in [-1, 1] { for z: Float in [-1, 1] {
                let point = rotation.act(halfExtents * SIMD3(x, y, z))
                let depth = dot(point, forward)
                distance = max(distance, depth + max(abs(point.x) / tanX, abs(dot(point, up)) / tanY) * 1.22)
                if yawOffset == 0 { bottom = min(bottom, point.y) }
            } } }
        }
        fittedDistance = resetFit ? distance : max(fittedDistance, distance)
        camera.camera.fieldOfViewInDegrees = 34
        camera.look(at: .zero, from: forward * max(0.5, fittedDistance), relativeTo: nil)
        ground.position.y = bottom - 0.012
    }
}

struct ModelStage: View {
    let product: Product
    var compact = false
    @EnvironmentObject private var store: MeltStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var scene = PreviewScene()
    @State private var loading = false
    @State private var loadFailed = false
    private enum Motion { case stopped, introduction, spin }
    @State private var motion = Motion.stopped
    @State private var visible = false
    @State private var introPending = false
    @State private var dragOrigin: SIMD2<Float>?

    private var modelKey: String { "\(product.id):\(product.usdzURL?.absoluteString ?? product.starterKey ?? ""):\(product.catalogKey ?? "")" }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RealityView { content in
                    content.camera = .virtual
                    content.add(scene.pivot)
                    content.add(scene.camera)
                    content.add(scene.ground)
                    let key = DirectionalLight()
                    key.light.intensity = 1800
                    key.shadow = .init(shadowProjection: .automatic(maximumDistance: 8), depthBias: 0.5)
                    key.look(at: .zero, from: [-3, 5, 4], relativeTo: nil)
                    content.add(key)
                    let fill = DirectionalLight()
                    fill.light.intensity = 450
                    fill.look(at: .zero, from: [3, 1, -2], relativeTo: nil)
                    content.add(fill)
                    scene.pose(resetFit: true)
                }
                .allowsHitTesting(!compact)
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    motion = .stopped
                    introPending = false
                    if dragOrigin == nil { dragOrigin = [scene.yaw, scene.pitch] }
                    guard let origin = dragOrigin else { return }
                    scene.yaw = origin.x + Float(value.translation.width) * 0.012
                    scene.pitch = min(.pi / 6, max(-.pi / 6, origin.y + Float(value.translation.height) * 0.008))
                    scene.pose()
                }.onEnded { _ in dragOrigin = nil })
                .accessibilityLabel("3D preview of \(product.name)")
                .accessibilityIdentifier("model-preview")
                .accessibilityValue(loading ? "loading" : (loadFailed ? "unavailable" : (scene.loadedKey == modelKey ? "ready" : "loading")))
                .accessibilityAction(named: "Rotate") {
                    motion = .stopped
                    scene.yaw += .pi / 4
                    scene.pose()
                }
                if loading { ProgressView("Loading model") }
                if loadFailed {
                    VStack(spacing: 10) {
                        Image(systemName: "cube.transparent").font(.largeTitle)
                        if !compact {
                            Text("Preview unavailable").font(.subheadline)
                            Button("Retry") { Task { await showModel() } }.font(.subheadline.bold())
                        }
                    }.padding().background(Studio.paper.opacity(0.95), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .onAppear { scene.viewport = geometry.size; scene.pose(resetFit: true) }
            .onChange(of: geometry.size) { _, size in scene.viewport = size; scene.pose(resetFit: true) }
        }
        .overlay(alignment: .bottomTrailing) {
            if !compact, !loadFailed, !loading {
                Button { motion = motion == .stopped ? .spin : .stopped } label: {
                    Image(systemName: motion != .stopped ? "pause" : "arrow.trianglehead.2.clockwise.rotate.90")
                        .font(.system(size: 20, weight: .regular)).frame(width: 44, height: 44)
                        .background(Studio.paper, in: Circle()).overlay(Circle().stroke(Studio.line))
                }.buttonStyle(.plain).accessibilityLabel(motion != .stopped ? "Pause" : "Spin").padding(8)
            }
        }
        .onAppear { visible = true; startIntroductionIfVisible() }
        .onDisappear { visible = false; introPending = false; motion = .stopped; dragOrigin = nil }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { motion = .stopped }
            else { startIntroductionIfVisible() }
        }
        .onChange(of: reduceMotion) { _, reduced in if reduced { motion = .stopped; introPending = false } }
        .onChange(of: product.filament) { _, _ in scene.appearance(for: product) }
        .onChange(of: product.colorCustomized) { _, _ in scene.appearance(for: product) }
        .task(id: modelKey) { await showModel() }
        .task(id: motion) {
            let movement = motion
            guard movement != .stopped, !compact, visible, scenePhase == .active else { return }
            // Reduce Motion prevents automatic movement; an explicit Spin remains available.
            guard movement != .introduction || !reduceMotion else { return }
            let start = ContinuousClock.now
            let initialYaw = scene.yaw
            while !Task.isCancelled, visible, scenePhase == .active, motion == movement {
                let duration = start.duration(to: .now).components
                let elapsed = Float(duration.seconds) + Float(duration.attoseconds) / 1e18
                if movement == .introduction {
                    let fraction = min(1, elapsed / 4)
                    let eased = fraction * fraction * (3 - 2 * fraction)
                    scene.yaw = initialYaw + eased * 20 * .pi / 180
                    scene.pose()
                    if fraction >= 1 { motion = .stopped; break }
                } else {
                    scene.yaw = initialYaw + elapsed * 0.24
                    scene.pose()
                }
                do { try await Task.sleep(for: .milliseconds(33)) } catch { break }
            }
        }
    }

    private func startIntroductionIfVisible() {
        guard introPending, visible, scenePhase == .active, !reduceMotion else { return }
        introPending = false
        motion = .introduction
    }

    @MainActor private func showModel() async {
        loading = true
        loadFailed = false
        motion = .stopped
        do {
            let model: Entity
            if product.starterKey == "friday-home" {
                guard let file = Bundle.main.url(forResource: "FridayHome", withExtension: "usdz") else {
                    throw MeltError("The opening model is unavailable")
                }
                model = try await Entity(contentsOf: file)
            } else if product.starterKey == "polka-man" {
                model = KeychainModel.make()
            } else if let remote = product.usdzURL {
                let file = try await cachedModelFile(for: remote, productId: product.id)
                do { model = try await Entity(contentsOf: file) }
                catch { try? FileManager.default.removeItem(at: file); throw error }
            } else if let key = product.catalogKey {
                model = try CatalogModel.make(key: key)
            } else if Fixtures.Scenario(rawValue: UserDefaults.standard.string(forKey: "MeltScenario") ?? "") != nil {
                model = fixtureModel(for: product)
            } else {
                throw MeltError("Preview unavailable")
            }
            guard !Task.isCancelled else { return }
            let bounds = model.visualBounds(relativeTo: nil)
            let longest = max(bounds.extents.x, bounds.extents.y, bounds.extents.z)
            guard longest.isFinite, longest > 0 else { throw MeltError("This model has no visible geometry") }
            let scale: Float = 1.15 / longest
            let fitted = Entity()
            fitted.addChild(model)
            fitted.scale = SIMD3(repeating: scale)
            fitted.position = -bounds.center * scale
            scene.pivot.children.removeAll()
            scene.pivot.addChild(fitted)
            scene.halfExtents = bounds.extents * scale / 2
            if scene.loadedKey != modelKey { scene.yaw = 35 * .pi / 180; scene.pitch = 0 }
            scene.loadedKey = modelKey
            scene.originals.removeAll()
            scene.rememberMaterials(model)
            scene.appearance(for: product)
            scene.pose(resetFit: true)
            if !compact, store.claimModelIntroduction(modelKey), !reduceMotion {
                introPending = true
                startIntroductionIfVisible()
            }
        } catch {
            guard !Task.isCancelled else { return }
            scene.pivot.children.removeAll()
            scene.originals.removeAll()
            loadFailed = true
        }
        loading = false
    }
}

private func cachedModelFile(for remote: URL, productId: String) async throws -> URL {
    let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("models", isDirectory: true)
    let file = folder.appendingPathComponent(productId).appendingPathExtension("usdz")
    if FileManager.default.fileExists(atPath: file.path) { return file }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let (downloaded, response) = try await URLSession.shared.download(from: remote)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw MeltError("Couldn't download the model") }
    if !FileManager.default.fileExists(atPath: file.path) {
        try FileManager.default.moveItem(at: downloaded, to: file)
    }
    return file
}

@MainActor private func applyFilament(_ filament: Filament, to entity: Entity) {
    if !entity.name.hasPrefix("fixed"), var model = entity.components[ModelComponent.self] {
        // Change only tint. Keep every texture, roughness/metallic map, normal map,
        // transparency setting, and material slot from the source USDZ.
        model.materials = model.materials.map { original in
            if var material = original as? PhysicallyBasedMaterial {
                material.baseColor.tint = UIColor(filament.color)
                return material
            }
            if var material = original as? SimpleMaterial {
                material.color.tint = UIColor(filament.color)
                return material
            }
            if var material = original as? UnlitMaterial {
                material.color.tint = UIColor(filament.color)
                return material
            }
            return original
        }
        entity.components.set(model)
    }
    for child in entity.children { applyFilament(filament, to: child) }
}

@MainActor enum KeychainModel {
    static func make() -> Entity {
        let root = Entity()
        func part(_ mesh: MeshResource, _ position: SIMD3<Float>, scale: SIMD3<Float> = [1, 1, 1], color: UIColor? = nil) -> ModelEntity {
            let material = SimpleMaterial(color: color ?? .white, roughness: 0.62, isMetallic: false)
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.position = position
            entity.scale = scale
            if color != nil { entity.name = "fixed-detail" }
            root.addChild(entity)
            return entity
        }
        // Rounded, connected vinyl-figure silhouette with a flattened back for a keychain.
        _ = part(.generateSphere(radius: 0.24), [0, 0.36, 0], scale: [1, 1.08, 0.66])
        _ = part(.generateBox(size: [0.34, 0.39, 0.21], cornerRadius: 0.105), [0, 0.02, 0])
        for sign: Float in [-1, 1] {
            let arm = part(.generateBox(size: [0.12, 0.34, 0.17], cornerRadius: 0.06), [sign * 0.21, 0.025, 0])
            arm.orientation = simd_quatf(angle: sign * 0.22, axis: [0, 0, 1])
            _ = part(.generateBox(size: [0.14, 0.28, 0.20], cornerRadius: 0.065), [sign * 0.095, -0.26, 0])
            _ = part(.generateBox(size: [0.16, 0.10, 0.24], cornerRadius: 0.04), [sign * 0.095, -0.38, 0.025])
        }
        // Actual open ring, not a solid disk; geometry is bundled as this mesh recipe.
        if let ring = try? torus(radius: 0.075, tube: 0.021) {
            _ = part(ring, [0, 0.65, 0])
        }
        let colors: [UIColor] = [UIColor(red: 0.94, green: 0.28, blue: 0.12, alpha: 1), .systemBlue, .systemYellow, .systemGreen, .systemPurple]
        let dots: [(Float, Float, Float, Float)] = [
            (-0.10, 0.49, 0.117, 0.037), (0.08, 0.52, 0.106, 0.031),
            (-0.17, 0.36, 0.112, 0.031), (0.16, 0.34, 0.123, 0.040),
            (-0.07, 0.22, 0.127, 0.027), (0.04, 0.12, 0.112, 0.038),
            (-0.10, 0.045, 0.11, 0.032), (0.10, -0.03, 0.112, 0.034),
            (-0.04, -0.12, 0.11, 0.038), (-0.23, 0.07, 0.083, 0.028),
            (0.22, -0.05, 0.087, 0.029), (-0.10, -0.25, 0.104, 0.030),
            (0.10, -0.30, 0.104, 0.032)
        ]
        for (index, dot) in dots.enumerated() {
            if dot.1 > 0.20 {
                let x = dot.0, y = dot.1 - 0.36
                let z: Float = 0.1584 * sqrt(max(0.01, 1 - x * x / (0.24 * 0.24) - y * y / (0.2592 * 0.2592)))
                let normal = normalize(SIMD3<Float>(x / (0.24 * 0.24), y / (0.2592 * 0.2592), z / (0.1584 * 0.1584)))
                let spot = part(.generateSphere(radius: dot.3), SIMD3<Float>(x, dot.1, z) + normal * 0.004,
                                scale: [1, 1, 0.13], color: colors[index % colors.count])
                spot.orientation = simd_quatf(from: [0, 0, 1], to: normal)
            } else {
                _ = part(.generateSphere(radius: dot.3), [dot.0, dot.1, dot.2], scale: [1, 1, 0.18], color: colors[index % colors.count])
            }
        }
        // Dark goggles make the face legible at thumbnail size.
        for x: Float in [-0.065, 0.065] {
            _ = part(.generateSphere(radius: 0.047), [x, 0.38, 0.154], scale: [1.15, 0.74, 0.24], color: UIColor(white: 0.12, alpha: 1))
            _ = part(.generateSphere(radius: 0.012), [x - 0.012, 0.392, 0.164], scale: [1, 1, 0.25], color: .white)
        }
        _ = part(.generateBox(size: [0.055, 0.018, 0.012], cornerRadius: 0.008), [0, 0.38, 0.16], color: UIColor(white: 0.12, alpha: 1))
        return root
    }

    private static func torus(radius: Float, tube: Float) throws -> MeshResource {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        let segments = 64, sides = 12
        for i in 0..<segments {
            let a = Float(i) / Float(segments) * 2 * .pi
            for j in 0..<sides {
                let b = Float(j) / Float(sides) * 2 * .pi
                positions.append([(radius + tube * cos(b)) * cos(a), (radius + tube * cos(b)) * sin(a), tube * sin(b)])
                normals.append([cos(b) * cos(a), cos(b) * sin(a), sin(b)])
                let p = UInt32(i * sides + j)
                let q = UInt32(((i + 1) % segments) * sides + j)
                let r = UInt32(((i + 1) % segments) * sides + (j + 1) % sides)
                let s = UInt32(i * sides + (j + 1) % sides)
                indices += [p, q, r, p, r, s]
            }
        }
        var descriptor = MeshDescriptor(name: "Attachment loop")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }
}

@MainActor private func fixtureModel(for product: Product) -> Entity {
    if product.name.localizedCaseInsensitiveContains("keychain") { return KeychainModel.make() }
    let root = Entity()
    func add(_ mesh: MeshResource, _ position: SIMD3<Float>, scale: SIMD3<Float> = [1, 1, 1]) {
        let entity = ModelEntity(mesh: mesh, materials: [SimpleMaterial()])
        entity.position = position
        entity.scale = scale
        root.addChild(entity)
    }
    if product.name.localizedCaseInsensitiveContains("vase") || product.name.localizedCaseInsensitiveContains("cup") {
        for i in 0..<18 {
            let ring = ModelEntity(mesh: .generateBox(size: [0.42, 0.035, 0.42], cornerRadius: 0.07), materials: [SimpleMaterial()])
            ring.position.y = Float(i) * 0.031 - 0.26
            ring.orientation = simd_quatf(angle: Float(i) * 0.065, axis: [0, 1, 0])
            root.addChild(ring)
        }
    } else if product.name.localizedCaseInsensitiveContains("bin") || product.name.localizedCaseInsensitiveContains("coaster") {
        add(.generateBox(size: [0.5, 0.22, 0.5], cornerRadius: 0.06), [0, -0.13, 0])
        add(.generateBox(size: [0.42, 0.22, 0.42], cornerRadius: 0.06), [0, 0.11, 0])
    } else {
        add(.generateSphere(radius: 0.25), [0, -0.1, 0], scale: [1, 0.9, 0.8])
        add(.generateSphere(radius: 0.20), [0, 0.23, 0])
        add(.generateCone(height: 0.16, radius: 0.07), [-0.12, 0.43, 0])
        add(.generateCone(height: 0.16, radius: 0.07), [0.12, 0.43, 0])
    }
    return root
}
