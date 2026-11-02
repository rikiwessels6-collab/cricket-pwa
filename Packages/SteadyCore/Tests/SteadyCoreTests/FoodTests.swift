import XCTest
@testable import SteadyCore

final class FoodTests: XCTestCase {
    let sample = """
    {"status":1,"product":{"code":"9300633603224","product_name":"Greek Yoghurt","brands":"Chobani, Other",
     "serving_quantity":"170","serving_size":"170 g",
     "nutriments":{"energy-kj_100g":"297","proteins_100g":9.6,"carbohydrates_100g":"4,1","fat_100g":0.2}}}
    """

    func testParsesProductWithKilojoulesAndStringNumbers() throws {
        let item = try XCTUnwrap(OpenFoodFacts.parseProduct(Data(sample.utf8)))
        XCTAssertEqual(item.name, "Greek Yoghurt")
        XCTAssertEqual(item.brand, "Chobani")
        XCTAssertEqual(item.per100.kcal, 297 / 4.184, accuracy: 0.01)
        XCTAssertEqual(item.per100.carbs, 4.1, accuracy: 0.001)
        XCTAssertEqual(item.servingGrams, 170)
        let m = item.macros(grams: 170)
        XCTAssertEqual(m.protein, 16.32, accuracy: 0.01)
    }

    func testMissingProductAndMissingEnergy() throws {
        XCTAssertNil(try OpenFoodFacts.parseProduct(Data(#"{"status":0}"#.utf8)))
        let noEnergy = #"{"status":1,"product":{"product_name":"X","nutriments":{"proteins_100g":1}}}"#
        XCTAssertNil(try OpenFoodFacts.parseProduct(Data(noEnergy.utf8)))
    }

    func testSearchSkipsUnusableProducts() throws {
        let json = #"{"products":[{"product_name":"Oats","nutriments":{"energy-kcal_100g":379,"proteins_100g":13}},{"product_name":""}]}"#
        let items = try OpenFoodFacts.parseSearch(Data(json.utf8))
        XCTAssertEqual(items.map(\.name), ["Oats"])
    }

    func testURLs() {
        XCTAssertNil(OpenFoodFacts.productURL(barcode: "123"))
        XCTAssertTrue(OpenFoodFacts.productURL(barcode: "9300633603224")!.absoluteString.contains("/product/9300633603224.json"))
        XCTAssertTrue(OpenFoodFacts.searchURL("weet bix")!.absoluteString.contains("tag_0=australia"))
    }

    func testMealSuggestion() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        func at(_ h: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: h))! }
        XCTAssertEqual(MealSlot.suggested(for: at(7), calendar: cal), .breakfast)
        XCTAssertEqual(MealSlot.suggested(for: at(12), calendar: cal), .lunch)
        XCTAssertEqual(MealSlot.suggested(for: at(19), calendar: cal), .dinner)
        XCTAssertEqual(MealSlot.suggested(for: at(15), calendar: cal), .snacks)
    }

    func testMacrosAdd() {
        let a = Macros(kcal: 100, protein: 10), b = Macros(kcal: 50, fat: 2)
        XCTAssertEqual((a + b).kcal, 150)
        XCTAssertEqual((a + b).fat, 2)
    }
}
