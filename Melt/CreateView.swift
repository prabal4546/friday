import SwiftUI

struct ProductDestination: Hashable {
    enum Action: Hashable { case view, order, publish }
    let id: String
    var action = Action.view
}

struct CreateView: View {
    @EnvironmentObject private var store: MeltStore
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var destination: ProductDestination?
    @State private var showsProfile = false
    @FocusState private var promptFocused: Bool

    private var current: Product {
        if let id = store.activeProductId, let product = store.product(id: id) { return product }
        var starter = Product.starter
        starter.filament = store.creatorFilament
        starter.colorCustomized = store.creatorColorCustomized
        return starter
    }
    private var connected: Bool { store.phase == .ready }
    private var trimmedPrompt: String { store.creatorPrompt.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isStarter: Bool { current.id == Product.starter.id }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("friday.").font(Studio.title(44)).tracking(-3)
                            Spacer()
                            Button { showsProfile = true } label: {
                                Image(systemName: "person.crop.circle").font(.system(size: 27, weight: .light)).frame(width: 44, height: 44)
                            }.buttonStyle(.plain).accessibilityLabel("Profile")
                        }
                        HStack(alignment: .top) {
                            Text(current.name).font(Studio.title(26)).tracking(-0.8).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 12)
                            if !isStarter {
                                Text(current.status.label.uppercased()).font(Studio.label).padding(.top, 7)
                            }
                        }
                        ModelPreview(product: current)
                            .frame(height: max(155, min(235, geometry.size.height * 0.28)))
                        HStack {
                            Text(isStarter ? "KEYCHAIN / 01" : "3D PREVIEW").font(Studio.label)
                            Spacer()
                            Text("Drag to rotate").font(.caption).foregroundStyle(Studio.muted)
                        }
                        StudioRule()
                        FilamentPicker(selection: Binding(get: { current.filament }, set: changeColor),
                                       originalSelected: current.hasOriginalAppearance && current.colorCustomized != true,
                                       reset: current.hasOriginalAppearance ? resetAppearance : nil)
                            .disabled(current.status == .published || current.status == .generating || isWorking)
                        if current.status == .ready || current.status == .published {
                            HStack(spacing: 12) {
                                Button { open(.order) } label: {
                                    HStack { Text("Order"); Spacer(); Image(systemName: "arrow.up.right") }.padding(.horizontal, 18)
                                }.buttonStyle(StudioButton())
                                Button { open(current.status == .published ? .view : .publish) } label: {
                                    Image(systemName: "square.and.arrow.up").frame(width: 52, height: 52)
                                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Studio.line))
                                }.buttonStyle(.plain).accessibilityLabel(current.status == .published ? "View listing" : "Publish")
                                if isStarter {
                                    Button { save() } label: {
                                        Image(systemName: "square.and.arrow.down").frame(width: 44, height: 52)
                                    }.buttonStyle(.plain).accessibilityLabel("Save design")
                                }
                            }.disabled(!connected || isWorking)
                        }
                        connectionStatus
                    }.padding(.horizontal, 24).padding(.top, 6).padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    composer.padding(.horizontal, 24).padding(.vertical, 12).background(Studio.paper)
                }
                .studioScreen()
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $destination) { route in
                ProductDetailView(productId: route.id, initialAction: route.action)
            }
            .sheet(isPresented: $showsProfile) { ProfileView() }
            .errorAlert("Couldn't complete that action", message: $errorMessage)
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Generation quality", selection: $store.generationQuality) {
                    ForEach(GenerationQuality.allCases) { quality in
                        Text(quality.label).tag(quality)
                    }
                }.pickerStyle(.segmented).frame(maxWidth: 190)
                    .accessibilityIdentifier("generation-quality")
                Spacer()
                Text("\(store.creatorPrompt.count)/400").font(Studio.label).foregroundStyle(Studio.muted)
            }
            TextField("Describe an object", text: $store.creatorPrompt, axis: .vertical)
                .font(.system(.body, design: .monospaced)).lineLimit(1...4)
                .focused($promptFocused).accessibilityIdentifier("prompt")
            StudioRule()
            HStack {
                if !isStarter {
                    Button("New") {
                        store.activeProductId = nil
                        store.creatorPrompt = Product.starter.prompt
                        store.creatorFilament = .bone
                        store.creatorColorCustomized = false
                    }.font(.subheadline).foregroundStyle(Studio.muted)
                }
                Spacer()
                Button { generate() } label: {
                    HStack(spacing: 12) {
                        Text(current.status == .failed ? "Retry" : "Generate").font(.subheadline.bold())
                        Image(systemName: "arrow.right").frame(width: 34, height: 34)
                            .foregroundStyle(Studio.paper).background(Studio.ink, in: Circle())
                    }
                }.buttonStyle(.plain).accessibilityIdentifier("generate")
                    .disabled(trimmedPrompt.isEmpty || trimmedPrompt.count > 400 || !connected || isWorking || current.status == .generating)
            }
        }.padding(16).overlay(RoundedRectangle(cornerRadius: 16).stroke(Studio.ink.opacity(0.65)))
    }

    @ViewBuilder private var connectionStatus: some View {
        switch store.phase {
        case .loading: ProgressView("Connecting").font(.caption)
        case .failed:
            HStack {
                Text("Couldn't connect").font(.subheadline)
                Spacer()
                Button("Try again") { Task { await store.load() } }.font(.subheadline.bold())
            }
        case .ready: EmptyView()
        }
    }

    private func generate() {
        promptFocused = false
        isWorking = true
        Task {
            defer { isWorking = false }
            do { store.activeProductId = try await store.generate(prompt: trimmedPrompt, filament: store.creatorFilament) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func changeColor(_ color: Filament) {
        store.creatorFilament = color
        if isStarter { store.creatorColorCustomized = true }
        if !isStarter {
            isWorking = true
            Task {
                defer { isWorking = false }
                do { try await store.setFilament(color, productId: current.id) }
                catch { errorMessage = error.localizedDescription }
            }
        }
    }

    private func resetAppearance() {
        if isStarter { store.creatorColorCustomized = false; return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do { try await store.resetAppearance(productId: current.id) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func save() {
        isWorking = true
        Task {
            defer { isWorking = false }
            do { _ = try await store.saveStarter(filament: store.creatorFilament) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func open(_ action: ProductDestination.Action) {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let id = isStarter ? try await store.saveStarter(filament: store.creatorFilament) : current.id
                destination = ProductDestination(id: id, action: action)
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
