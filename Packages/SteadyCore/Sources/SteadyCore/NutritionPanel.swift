import Foundation

/// What was read from a photo of a nutrition information panel. Always shown to the user to check.
public struct PanelReading: Equatable, Sendable {
    public var kcal: Double?
    public var protein: Double?
    public var carbs: Double?
    public var fat: Double?
    public var fibre: Double?
    public var servingGrams: Double?
    /// True when the panel had a per-serve and a per-100 g column, so the per-100 g one could be picked out.
    public var foundBothColumns = false

    public var foundAnything: Bool { kcal != nil || protein != nil || carbs != nil || fat != nil }
}

/// Reads an Australian-style panel from lines of text (one line per table row), using the per 100 g column.
public enum NutritionPanel {
    public static func parse(_ rows: [String]) -> PanelReading {
        let lines = rows.map(normalise)
        var reading = PanelReading()

        // Which column is "per 100 g"? Default: the last one, as on most labels.
        var per100First = false
        for l in lines where l.contains("per 100") || l.contains("per100") {
            if let r100 = l.range(of: "per 100") ?? l.range(of: "per100") {
                let before = l[..<r100.lowerBound]
                per100First = !(before.contains("serv") || before.contains("per "))
            }
            break
        }

        var both = false
        func pick(_ values: [Double]) -> Double? {
            guard !values.isEmpty else { return nil }
            if values.count >= 2 { both = true }
            return per100First ? values.first : values.last
        }

        var kj: [Double] = [], cal: [Double] = []
        for l in lines {
            if l.contains("serving size") || l.contains("serve size") || l.contains("serv size") {
                if reading.servingGrams == nil, let v = numbers(l, units: ["g", "ml"]).first { reading.servingGrams = v }
                continue
            }
            if l.contains("energy") || l.hasPrefix("kj") {
                kj = numbers(l, units: ["kj"])
                cal = numbers(l, units: ["kcal", "cal"])
                continue
            }
            let isSub = l.hasPrefix("-") || l.hasPrefix("•") || l.contains("saturated") || l.contains("trans")
                || l.contains("polyunsat") || l.contains("monounsat") || l.contains("omega")
            if l.contains("protein") {
                if reading.protein == nil { reading.protein = pick(numbers(l, units: ["g"])) }
            } else if l.contains("fibre") || l.contains("fiber") {
                if reading.fibre == nil { reading.fibre = pick(numbers(l, units: ["g"])) }
            } else if l.contains("carbohydrate") || l.contains("carbs") {
                if reading.carbs == nil, !isSub { reading.carbs = pick(numbers(l, units: ["g"])) }
            } else if l.contains("sugar") || l.contains("sodium") || l.contains("salt") {
                continue
            } else if l.contains("fat") {
                if reading.fat == nil, !isSub { reading.fat = pick(numbers(l, units: ["g"])) }
            }
        }
        if let c = pick(cal) {
            reading.kcal = c
        } else if let k = pick(kj) {
            reading.kcal = (k / 4.184).rounded()
        }
        reading.foundBothColumns = both
        // A per-100 g value can't be more than 100 g, and food has at most about 900 kcal per 100 g.
        if let k = reading.kcal, k > 950 { reading.kcal = nil }
        if let p = reading.protein, p > 100 { reading.protein = nil }
        if let c = reading.carbs, c > 100 { reading.carbs = nil }
        if let f = reading.fat, f > 100 { reading.fat = nil }
        if let f = reading.fibre, f > 100 { reading.fibre = nil }
        return reading
    }

    private static func normalise(_ s: String) -> String {
        var t = s.lowercased()
        // "6,0 g" is a decimal comma.
        t = t.replacingOccurrences(of: #"(\d),(\d)"#, with: "$1.$2", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// Numbers directly followed by one of the units, in the order they appear ("<1 g" gives 1).
    static func numbers(_ line: String, units: [String]) -> [Double] {
        let pattern = #"(\d+(?:\.\d+)?)\s*("# + units.joined(separator: "|") + #")(?![a-z])"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(line.startIndex..., in: line)
        return re.matches(in: line, range: range).compactMap { m in
            Range(m.range(at: 1), in: line).flatMap { Double(line[$0]) }
        }
    }
}
