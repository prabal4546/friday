import SwiftUI

struct CreateView: View {
    @EnvironmentObject private var store: MeltStore
    @State private var prompt = ""
    @State private var filament = Filament.tangerine
    @State private var latestProductId: String?
    @State private var errorMessage: String?
    @FocusState private var promptFocused: Bool

    private var trimmedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            PhaseView {
                Form {
                    Section("Describe your product") {
                        TextField("A fox that holds my earbuds", text: $prompt, axis: .vertical)
                            .lineLimit(3...6)
                            .focused($promptFocused)
                            .accessibilityIdentifier("prompt")
                    }
                    Section("Filament") {
                        FilamentPicker(selection: $filament)
                        LabeledContent("Color", value: filament.label)
                    }
                    Section {
                        Button("Generate model") {
                            promptFocused = false
                            Task {
                                do {
                                    latestProductId = try await store.generate(prompt: trimmedPrompt, filament: filament)
                                    prompt = ""
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                            }
                        }
                        .disabled(trimmedPrompt.isEmpty)
                    }
                    if let latestProductId, let product = store.product(id: latestProductId) {
                        Section("Latest design") {
                            NavigationLink {
                                ProductDetailView(productId: product.id)
                            } label: {
                                ProductRow(product: product)
                            }
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Create")
            .errorAlert("Couldn't start generating", message: $errorMessage)
        }
    }
}
