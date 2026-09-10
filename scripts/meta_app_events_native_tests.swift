import Foundation

@main
enum MetaNativeTests {
  static func main() {
    func allowed(_ values: [String: Any] = [:], status: MetaCMPStatus = .notRequired,
                 resolved: Bool = true, att: Bool = false) -> MetaPermission {
      MetaAppEventsPolicy.evaluate(resolved: resolved, status: status, values: values, attAuthorized: att)
    }
    precondition(!allowed(resolved: false).collection)
    precondition(!MetaAppEventsPolicy.hasConfiguration([:]))
    precondition(!MetaAppEventsPolicy.hasConfiguration(["FacebookAppID": "$(META_APP_ID)",
      "FacebookClientToken": "$(META_CLIENT_TOKEN)"]))
    precondition(MetaAppEventsPolicy.hasConfiguration(["FacebookAppID": "1600882908142439",
      "FacebookClientToken": "0123456789abcdef0123456789abcdef"]))
    precondition(!allowed(status: .unknown).collection)
    precondition(allowed().collection && !allowed().advertiserID)
    precondition(allowed(att: true).advertiserID)
    for ac in ["1~89", "2~89~dv.", "2~89~dv", "2~1.89.100~dv.4"] {
      let values: [String: Any] = ["IABTCF_gdprApplies": 1, "IABTCF_AddtlConsent": ac]
      precondition(allowed(values, status: .obtained).collection)
      precondition(!allowed(values, status: .notRequired).collection)
    }
    for ac in ["2~~dv.89", "2~1549~dv.89", "2~89~bad", "3~89", "1~89.", "2~89~dv..", "2~0.89~dv."] {
      precondition(!allowed(["IABTCF_gdprApplies": 1, "IABTCF_AddtlConsent": ac], status: .obtained).collection)
    }
    precondition(!allowed(["IABTCF_gdprApplies": "bad"]).collection)
    precondition(!allowed(["IABTCF_gdprApplies": 0, "IABGPP_TCFEU2_gdprApplies": 1]).collection)
    precondition(!allowed(["IABGPP_GppSID": "99"]).collection)
    precondition(!allowed(["IABGPP_GppSID": "7"]).collection)
    precondition(allowed(["IABGPP_GppSID": "-1"]).collection)
    precondition(!allowed(["IABGPP_HDR_GppString": "unknown"]).collection)
    precondition(!allowed(["IABGPP_GppSID": "-1", "IABGPP_HDR_GppString": 123]).collection)
    for usp in ["1YYN", "bad", "1Y-N"] {
      precondition(!allowed(["IABUSPrivacy_String": usp]).collection)
    }
    precondition(allowed(["IABUSPrivacy_String": "1YNN"]).collection)
    precondition(allowed(["IABUSPrivacy_String": "1---"]).collection)
    // CA does not define TargetedAdvertisingOptOut; VA does not define Sharing/Gpc.
    var ca: [String: Any] = ["IABGPP_GppSID": "8", "IABGPP_USCA_SaleOptOut": 2,
                           "IABGPP_USCA_SharingOptOut": 2, "IABGPP_USCA_Gpc": false]
    precondition(allowed(ca).collection)
    ca["IABGPP_USCA_Gpc"] = true
    precondition(!allowed(ca).collection)
    ca["IABGPP_USCA_Gpc"] = false
    ca["IABGPP_USCA_SharingOptOut"] = 1
    precondition(!allowed(ca).collection)
    precondition(allowed(["IABGPP_GppSID": "9", "IABGPP_USVA_SaleOptOut": 2,
                          "IABGPP_USVA_TargetedAdvertisingOptOut": 2]).collection)
    for (id, (prefix, fields)) in MetaAppEventsPolicy.usSections {
      var values: [String: Any] = ["IABGPP_GppSID": String(id)]
      for field in fields { values["IABGPP_\(prefix)_\(field)"] = field == "Gpc" ? 0 : 2 }
      precondition(allowed(values).collection)
      for field in fields {
        let key = "IABGPP_\(prefix)_\(field)"
        let original = values[key]
        values[key] = 1
        precondition(!allowed(values).collection)
        values.removeValue(forKey: key)
        precondition(!allowed(values).collection)
        values[key] = original
      }
    }

    let sdk = RecordingSDK()
    var foreground = false
    var permission = MetaPermission(collection: true, advertiserID: false)
    let lifecycle = MetaAppEventsLifecycle(sdk: sdk, permission: { resolved in
      resolved ? permission : .denied
    }, isForeground: { foreground })
    lifecycle.updateConsent(resolved: true)
    precondition(sdk.calls.isEmpty, "Background Health launch must not initialize SDK")
    foreground = true
    lifecycle.becameActive()
    precondition(sdk.calls == ["initialize:false", "resume:false", "activate"])
    lifecycle.becameActive() // temporary ATT/system alert return, same foreground epoch
    precondition(sdk.calls.filter { $0 == "activate" }.count == 1)
    precondition(lifecycle.log(event: "shopViewed"))
    precondition(!lifecycle.log(event: "registrationCompleted"))
    precondition(!lifecycle.log(event: "purchase"))
    lifecycle.updateConsent(resolved: false) // privacy options opening
    precondition(sdk.calls.last == "suspend")
    precondition(!lifecycle.log(event: "raceJoined"))
    permission = MetaPermission(collection: true, advertiserID: true)
    lifecycle.updateConsent(resolved: true)
    precondition(sdk.calls.last == "resume:true")
    precondition(sdk.calls.filter { $0 == "activate" }.count == 1)
    foreground = false
    lifecycle.enteredBackground()
    foreground = true
    permission = .denied
    lifecycle.becameActive()
    precondition(sdk.calls.last == "suspend")
    permission = MetaPermission(collection: true, advertiserID: false)
    lifecycle.updateConsent(resolved: true)
    precondition(sdk.calls.filter { $0 == "activate" }.count == 2)
    precondition(sdk.calls.filter { $0.hasPrefix("initialize") }.count == 1)
    print("Meta native policy and lifecycle tests passed.")
  }
}

private final class RecordingSDK: MetaAppEventsSDK {
  var calls: [String] = []
  func initialize(advertiserID: Bool) { calls.append("initialize:\(advertiserID)") }
  func resume(advertiserID: Bool) { calls.append("resume:\(advertiserID)") }
  func suspend() { calls.append("suspend") }
  func activate() { calls.append("activate") }
  func log(name: String) { calls.append("log:\(name)") }
}
