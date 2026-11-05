import XCTest
@testable import SteadyCore

final class NutritionPanelTests: XCTestCase {
    func testPerServeThenPer100() {
        let r = NutritionPanel.parse([
            "NUTRITION INFORMATION", "Servings per package: 8", "Serving size: 30 g",
            "Average Quantity Per Serve Per 100 g",
            "Energy 480 kJ 1600 kJ", "Protein 6.0 g 20.0 g", "Fat, total 3.0 g 10.0 g",
            "- saturated 0.5 g 1.7 g", "Carbohydrate 15.0 g 50.0 g", "- sugars 2.0 g 6.7 g",
            "Dietary fibre 3.0 g 10.0 g", "Sodium 90 mg 300 mg",
        ])
        XCTAssertEqual(r.servingGrams, 30)
        XCTAssertEqual(r.kcal, 382)          // 1600 kJ / 4.184
        XCTAssertEqual(r.protein, 20)
        XCTAssertEqual(r.fat, 10)
        XCTAssertEqual(r.carbs, 50)
        XCTAssertEqual(r.fibre, 10)
        XCTAssertTrue(r.foundBothColumns)
    }

    func testPer100FirstWithCalories() {
        let r = NutritionPanel.parse([
            "Serving size: 250 ml", "Per 100 g Per serve",
            "Energy 1600 kJ (382 Cal) 4000 kJ (955 Cal)",
            "Protein 20,5 g 51,3 g", "Fat total 10 g 25 g", "Carbohydrate 50 g 125 g",
        ])
        XCTAssertEqual(r.kcal, 382)
        XCTAssertEqual(r.protein, 20.5)
        XCTAssertEqual(r.servingGrams, 250)
        XCTAssertNil(r.fibre)
    }

    func testSubRowsAndSugarsAreNotMistakenForTotals() {
        let r = NutritionPanel.parse(["Per serve Per 100 g", "Fat, saturated 1 g 4 g", "of which sugars 3 g 12 g", "Fat, total 5 g 20 g"])
        XCTAssertEqual(r.fat, 20)
        XCTAssertNil(r.carbs)
    }

    func testSingleColumnAndLessThan() {
        let r = NutritionPanel.parse(["Energy 250 kcal", "Protein <1 g", "Carbohydrate 60 g", "Fat 0.4 g"])
        XCTAssertEqual(r.kcal, 250)
        XCTAssertEqual(r.protein, 1)
        XCTAssertFalse(r.foundBothColumns)
    }

    func testNonsenseIsRejected() {
        let r = NutritionPanel.parse(["hello world", "Protein 500 g 800 g"])
        XCTAssertFalse(r.foundAnything)
    }
}
