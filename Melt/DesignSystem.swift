import SwiftUI

enum Studio {
    static let paper = Color(red: 0.96, green: 0.94, blue: 0.90)
    static let ink = Color(red: 0.12, green: 0.13, blue: 0.12)
    static let orange = Color(red: 0.94, green: 0.31, blue: 0.12)
    static let muted = Color(red: 0.43, green: 0.43, blue: 0.39)
    static let line = ink.opacity(0.16)
    static func title(_ size: CGFloat = 34) -> Font { .system(size: size, weight: .heavy, design: .rounded) }
    static let label = Font.system(.caption, design: .monospaced).weight(.medium)
}

struct StudioButton: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var secondary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded).weight(.bold))
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(secondary ? Studio.ink : .white)
            .background(secondary ? Studio.ink.opacity(0.07) : Studio.orange)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .opacity(!isEnabled ? 0.45 : (configuration.isPressed ? 0.7 : 1))
    }
}

struct StudioRule: View {
    var body: some View { Rectangle().fill(Studio.line).frame(height: 1).accessibilityHidden(true) }
}

struct StudioHeading: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Studio.title()).tracking(-1.2)
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(Studio.muted) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StudioEmpty: View {
    let title: String
    let detail: String
    var symbol = "cube.transparent"
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 32, weight: .light))
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(Studio.muted).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 44)
    }
}

struct StudioSegments<Value: Hashable>: View {
    let values: [Value]
    @Binding var selection: Value
    let label: (Value) -> String
    var body: some View {
        HStack(spacing: 4) {
            ForEach(values, id: \.self) { value in
                Button { selection = value } label: {
                    Text(label(value)).font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .foregroundStyle(selection == value ? Studio.paper : Studio.muted)
                        .background(selection == value ? Studio.ink : .clear, in: RoundedRectangle(cornerRadius: 9))
                }.buttonStyle(.plain)
                    .accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }.padding(4).background(Studio.ink.opacity(0.045), in: RoundedRectangle(cornerRadius: 13))
    }
}

extension View {
    func studioScreen() -> some View {
        self.background(Studio.paper).foregroundStyle(Studio.ink)
            .toolbarBackground(Studio.paper, for: .navigationBar)
    }
}

struct ProductTile: View {
    let product: Product
    var showsCreator = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProductArtwork(product: product)
                .frame(height: 170).background(Studio.ink.opacity(0.025))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            Text(product.name).font(.system(.subheadline, design: .rounded).weight(.bold)).lineLimit(2)
            Text(showsCreator ? product.creatorName : product.status.label)
                .font(Studio.label).foregroundStyle(Studio.muted).lineLimit(1)
            if product.status == .published {
                HStack {
                    Text(dollars(product.priceCents)).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(product.salesCount) sold").font(.caption).foregroundStyle(Studio.muted)
                }
            }
        }.foregroundStyle(Studio.ink).accessibilityElement(children: .combine)
    }
}

struct ProductArtwork: View {
    let product: Product
    var body: some View {
        if let url = product.thumbnailURL, product.colorCustomized != true {
            AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: {
                ModelPreview(product: product, compact: true)
            }
        } else {
            ModelPreview(product: product, compact: true)
        }
    }
}
