import SwiftUI

struct FilamentPicker: View {
    @Binding var selection: Filament

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Filament.allCases) { option in
                    Button {
                        selection = option
                    } label: {
                        Circle()
                            .fill(option.color)
                            .frame(width: 36, height: 36)
                            .overlay {
                                Circle().strokeBorder(.primary, lineWidth: option == selection ? 3 : 0)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.label)
                    .accessibilityAddTraits(option == selection ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        }
    }
}
