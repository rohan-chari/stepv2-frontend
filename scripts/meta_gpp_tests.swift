import Foundation

@main
enum MetaGPPTests {
  static func main() throws {
    let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
    let fixtures = try JSONDecoder().decode([Fixture].self, from: data)
    for fixture in fixtures {
      let values: [String: Any] = ["IABGPP_GppSID": fixture.sid, "IABGPP_HDR_GppString": fixture.gpp]
      for status: MetaCMPStatus in [.notRequired, .obtained] {
        let permission = MetaAppEventsPolicy.evaluate(resolved: true, status: status,
          values: values, attAuthorized: true)
        precondition(permission.collection == fixture.allowed, fixture.label + " collection")
        precondition(permission.advertiserID == fixture.allowed, fixture.label + " ATT")
      }
      precondition(!MetaAppEventsPolicy.evaluate(resolved: false, status: .obtained,
        values: values, attAuthorized: true).collection)
    }
    let allowed = "DBABLA~CAAqAAAAAABA.QA"
    func permits(_ gpp: String, sid: String = "7", extra: [String: Any] = [:]) -> Bool {
      var values: [String: Any] = ["IABGPP_GppSID": sid, "IABGPP_HDR_GppString": gpp]
      values.merge(extra) { _, new in new }
      return MetaAppEventsPolicy.evaluate(resolved: true, status: .obtained,
        values: values, attAuthorized: true).collection
    }
    // A valid compact signal cannot override a denial in another supplied signal.
    precondition(!permits(allowed, extra: ["IABGPP_USNAT_SaleOptOut": 1]))
    precondition(!permits(allowed, extra: ["IABGPP_USNAT_Gpc": 1]))
    precondition(!permits(allowed, extra: ["IABTCF_gdprApplies": 1]))
    precondition(!permits(allowed, extra: ["IABUSPrivacy_String": "1YYN"]))
    precondition(!permits(allowed, sid: "8"))
    precondition(!permits(allowed, sid: "7_99"))
    for malformed in ["", "garbage", "DBABLA", "DBABLA~", "DBABLA~C", "DBABLA~CAAqAAAAAABA.bad",
                      allowed + "~extra", allowed + ".QA", "DBABLA~DAAqAAAAAABA.QA",
                      "DBABLA~CAAqAAAAAABA.QB", "DBABLA~CAAqAAAAAABA=", String(repeating: "A", count: 20000)] {
      precondition(!permits(malformed), "Malformed GPP must fail closed: " + String(malformed.prefix(80)))
    }
    print("Meta GPP: \(fixtures.count) independent IAB fixtures and malformed/contradictory signal checks passed.")
  }
  private struct Fixture: Decodable {
    let label: String
    let sid: String
    let gpp: String
    let allowed: Bool
  }
}
