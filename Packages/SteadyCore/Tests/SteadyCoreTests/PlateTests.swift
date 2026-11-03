import XCTest
@testable import SteadyCore

final class PlateTests: XCTestCase {
    let sample = """
    {"items":[{"name":"Cooked rice","grams":180,"kcal":234,"protein":4.7,"carbs":50,"fat":0.5,"fibre":0.9,"confidence":"high","basis":"area x height"},
              {"name":"Chicken curry","grams":220,"kcal":330,"protein":28,"carbs":10,"fat":20,"fibre":2,"confidence":"low","basis":"mixed dish"}],
     "questions":[{"id":"oil","text":"Cooked in oil?","options":[
        {"label":"None","kcal":0,"fat":0,"carbs":0,"protein":0},
        {"label":"1 tbsp","kcal":120,"fat":14,"carbs":0,"protein":0}]}],
     "notFood":false}
    """

    func testDecodeAndTotals() throws {
        let r = try PlateResult.decode(Data(sample.utf8))
        XCTAssertEqual(r.items.count, 2)
        XCTAssertEqual(PlateMath.overall(r.items), .low)
        XCTAssertEqual(PlateMath.total(items: r.items, questions: r.questions, answers: [:]).kcal, 564, accuracy: 0.01)
        XCTAssertEqual(PlateMath.total(items: r.items, questions: r.questions, answers: ["oil": 1]).kcal, 684, accuracy: 0.01)
        XCTAssertEqual(PlateMath.total(items: r.items, questions: r.questions, answers: ["oil": 9]).kcal, 564, accuracy: 0.01)
    }

    func testScalingKeepsProportions() throws {
        let rice = try PlateResult.decode(Data(sample.utf8)).items[0]
        let half = rice.scaled(toGrams: 90)
        XCTAssertEqual(half.kcal, 117, accuracy: 0.01)
        XCTAssertEqual(rice.per100?.kcal ?? 0, 130, accuracy: 0.01)
        XCTAssertNil(rice.scaled(toGrams: 0).per100)
    }

    func testRequestOmitsMissingFieldsAndTrimsNote() throws {
        let req = PlateRequest(imageBase64: "abc", note: "   ")
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(req)) as! [String: Any]
        XCTAssertNil(json["depth"])
        XCTAssertNil(json["note"])
        XCTAssertEqual(json["mediaType"] as? String, "image/jpeg")
        XCTAssertEqual(PlateRequest(imageBase64: "x", note: String(repeating: "a", count: 500)).note?.count, 300)
    }
}
