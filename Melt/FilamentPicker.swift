import SwiftUI

struct FilamentPicker: View {
    @Binding var selection: Filament
    var originalSelected = false
    var reset: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("COLOR / \(originalSelected ? "ORIGINAL" : selection.label.uppercased())").font(Studio.label).foregroundStyle(Studio.muted)
                Spacer()
                if let reset {
                    Button("Original", action: reset).font(.caption.weight(.semibold)).disabled(originalSelected)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Filament.allCases) { option in
                        Button { selection = option } label: {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(option.color.gradient)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(.black.opacity(0.10), lineWidth: 2).padding(6)
                                }
                                .frame(width: 46, height: 46)
                                .shadow(color: .black.opacity(0.12), radius: 2, y: 3)
                                .padding(5)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 17)
                                        .strokeBorder(Studio.ink, lineWidth: !originalSelected && option == selection ? 2 : 0)
                                }
                        }.buttonStyle(.plain)
                            .accessibilityLabel(option.label)
                            .accessibilityAddTraits(!originalSelected && option == selection ? .isSelected : [])
                    }
                }.padding(.vertical, 3)
            }
        }
    }
}
