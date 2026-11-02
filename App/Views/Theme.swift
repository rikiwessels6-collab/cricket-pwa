import SwiftUI

/// Boundary Line palette: night sky, emerald, gold. Dark-first.
extension Color {
    static let night = Color("Night")
    static let surface = Color("Surface")
    static let surfaceRaised = Color("SurfaceRaised")
    static let hairline = Color("Hairline")
    static let emerald = Color("Emerald")
    static let gold = Color("Gold")
    static let goldDeep = Color("GoldDeep")
    static let ink = Color("Ink")
    static let inkMuted = Color("InkMuted")
}

extension LinearGradient {
    /// The arc in the Boundary Line mark: emerald into gold.
    static let brand = LinearGradient(colors: [.emerald, .gold], startPoint: .leading, endPoint: .trailing)
    static let night = LinearGradient(colors: [Color("SurfaceRaised"), Color("Night")], startPoint: .top, endPoint: .bottom)
}

/// A raised card on the night background.
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.hairline, lineWidth: 1))
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }

    /// Lists and forms on the night background.
    func themedList() -> some View {
        self.scrollContentBackground(.hidden)
            .background(Color.night.ignoresSafeArea())
            .listRowBackground(Color.surface)
    }
}

/// Thin emerald-to-gold progress bar.
struct BrandProgress: View {
    let value: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.hairline)
                Capsule().fill(LinearGradient.brand)
                    .frame(width: max(6, g.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: 6)
        .animation(.snappy, value: value)
        .accessibilityElement()
        .accessibilityValue("\(Int(value * 100)) percent")
    }
}
