import Foundation

/// Nutrition per 100 g (or 100 ml), the way labels and Open Food Facts give it.
public struct Per100: Codable, Equatable, Sendable {
    public var kcal: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    public var fibre: Double
    public init(kcal: Double, protein: Double, carbs: Double, fat: Double, fibre: Double = 0) {
        self.kcal = kcal; self.protein = protein; self.carbs = carbs; self.fat = fat; self.fibre = fibre
    }
}

public struct Macros: Equatable, Sendable {
    public var kcal: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    public var fibre: Double
    public init(kcal: Double = 0, protein: Double = 0, carbs: Double = 0, fat: Double = 0, fibre: Double = 0) {
        self.kcal = kcal; self.protein = protein; self.carbs = carbs; self.fat = fat; self.fibre = fibre
    }
    public static func + (a: Macros, b: Macros) -> Macros {
        Macros(kcal: a.kcal + b.kcal, protein: a.protein + b.protein, carbs: a.carbs + b.carbs,
               fat: a.fat + b.fat, fibre: a.fibre + b.fibre)
    }
}

/// A food you can log: from a barcode, a search, or entered by hand.
public struct FoodItem: Codable, Equatable, Sendable, Identifiable {
    public var id: String               // barcode, or a generated id for custom foods
    public var name: String
    public var brand: String?
    public var barcode: String?
    public var per100: Per100
    public var servingGrams: Double?    // one serving as printed on the pack
    public var servingLabel: String?

    public init(id: String, name: String, brand: String?, barcode: String?, per100: Per100,
                servingGrams: Double?, servingLabel: String?) {
        self.id = id; self.name = name; self.brand = brand; self.barcode = barcode
        self.per100 = per100; self.servingGrams = servingGrams; self.servingLabel = servingLabel
    }

    public func macros(grams: Double) -> Macros {
        let f = grams / 100
        return Macros(kcal: per100.kcal * f, protein: per100.protein * f, carbs: per100.carbs * f,
                      fat: per100.fat * f, fibre: per100.fibre * f)
    }

    public var defaultGrams: Double { servingGrams ?? 100 }
}

public enum MealSlot: String, Codable, CaseIterable, Sendable, Identifiable {
    case breakfast, lunch, dinner, snacks
    public var id: String { rawValue }
    public var label: String { rawValue.capitalized }

    /// The likely meal for a time of day.
    public static func suggested(for date: Date, calendar: Calendar = .current) -> MealSlot {
        switch calendar.component(.hour, from: date) {
        case 4..<11: return .breakfast
        case 11..<15: return .lunch
        case 17..<22: return .dinner
        default: return .snacks
        }
    }
}

/// How a food entry was made. Kept on every entry with its timestamps.
public enum FoodSource: String, Codable, CaseIterable, Sendable {
    case barcode, search, recent, saved, manual, photo
}

/// Open Food Facts (openfoodfacts.org, data under the ODbL licence).
/// Only the barcode or search words are sent; nothing about the user.
public enum OpenFoodFacts {
    public static let userAgent = "SteadyStrength/0.1 (iOS)"
    static let fields = "code,product_name,product_name_en,brands,nutriments,serving_quantity,serving_size"

    public static func productURL(barcode: String) -> URL? {
        let digits = barcode.filter(\.isNumber)
        guard digits.count >= 8 else { return nil }
        return URL(string: "https://world.openfoodfacts.org/api/v2/product/\(digits).json?fields=\(fields)")
    }

    /// Search, preferring products sold in Australia.
    public static func searchURL(_ query: String, page: Int = 1) -> URL? {
        var c = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl")!
        c.queryItems = [
            .init(name: "search_terms", value: query), .init(name: "search_simple", value: "1"),
            .init(name: "action", value: "process"), .init(name: "json", value: "1"),
            .init(name: "page_size", value: "25"), .init(name: "page", value: String(page)),
            .init(name: "tagtype_0", value: "countries"), .init(name: "tag_contains_0", value: "contains"),
            .init(name: "tag_0", value: "australia"), .init(name: "fields", value: fields),
        ]
        return c.url
    }

    struct ProductResponse: Decodable { let status: Int?; let product: Product? }
    struct SearchResponse: Decodable { let products: [Product] }

    struct Product: Decodable {
        let code: String?
        let product_name: String?
        let product_name_en: String?
        let brands: String?
        let nutriments: [String: Flexible]?
        let serving_quantity: Flexible?
        let serving_size: String?
    }

    /// OFF numbers arrive as numbers or strings.
    struct Flexible: Decodable {
        let value: Double?
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let d = try? c.decode(Double.self) { value = d }
            else if let s = try? c.decode(String.self) { value = Double(s.replacingOccurrences(of: ",", with: ".")) }
            else { value = nil }
        }
    }

    static func item(from p: Product) -> FoodItem? {
        let name = (p.product_name_en?.isEmpty == false ? p.product_name_en : p.product_name)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let name, !name.isEmpty, let n = p.nutriments else { return nil }
        func v(_ k: String) -> Double? { n[k]?.value }
        // Energy: prefer kcal; otherwise convert kJ (Australian labels are kJ-first).
        let kcal = v("energy-kcal_100g") ?? v("energy_100g").map { $0 / 4.184 } ?? v("energy-kj_100g").map { $0 / 4.184 }
        guard let kcal else { return nil }
        let per = Per100(kcal: kcal, protein: v("proteins_100g") ?? 0, carbs: v("carbohydrates_100g") ?? 0,
                         fat: v("fat_100g") ?? 0, fibre: v("fiber_100g") ?? 0)
        let code = p.code ?? UUID().uuidString
        let brand = p.brands?.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) }
        let serving = p.serving_quantity?.value.flatMap { $0 > 0 ? $0 : nil }
        return FoodItem(id: code, name: name, brand: brand, barcode: p.code, per100: per,
                        servingGrams: serving, servingLabel: p.serving_size)
    }

    public static func parseProduct(_ data: Data) throws -> FoodItem? {
        let r = try JSONDecoder().decode(ProductResponse.self, from: data)
        guard r.status != 0, let p = r.product else { return nil }
        return item(from: p)
    }

    public static func parseSearch(_ data: Data) throws -> [FoodItem] {
        try JSONDecoder().decode(SearchResponse.self, from: data).products.compactMap(item(from:))
    }
}
