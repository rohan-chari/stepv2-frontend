import Foundation

enum MetaCMPStatus { case unknown, required, notRequired, obtained }

struct MetaPermission {
  let collection: Bool
  let advertiserID: Bool
  static let denied = MetaPermission(collection: false, advertiserID: false)
}

/// Reads only current CMP-provided signals. Meta is Google AC provider 89,
/// not a TCF GVL vendor: no invented purpose/vendor bit mask is applied.
enum MetaAppEventsPolicy {
  static func hasConfiguration(_ values: [String: Any]) -> Bool {
    guard let appID = values["FacebookAppID"] as? String,
          appID.range(of: "^[0-9]+$", options: .regularExpression) != nil,
          let token = values["FacebookClientToken"] as? String,
          token.range(of: "^[0-9a-fA-F]{32}$", options: .regularExpression) != nil else { return false }
    return true
  }
  // IAB GPP section schemas: CA has sharing rather than targeted-advertising;
  // several state sections do not define a GPC subsection.
  static let usSections: [Int: (String, [String])] = {
    let prefixes = [7: "USNAT", 8: "USCA", 9: "USVA", 10: "USCO", 11: "USUT",
                    12: "USCT", 13: "USFL", 14: "USMT", 15: "USOR", 16: "USTX",
                    17: "USDE", 18: "USIA", 19: "USNE", 20: "USNH", 21: "USNJ",
                    22: "USTN", 23: "USMN", 24: "USMD", 25: "USIN", 26: "USKY", 27: "USRI"]
    let withoutGpc: Set<Int> = [9, 11, 13, 25, 26, 27]
    return Dictionary(uniqueKeysWithValues: prefixes.map { id, prefix in
      var fields = ["SaleOptOut"]
      if id == 7 || id == 8 { fields.append("SharingOptOut") }
      if id != 8 { fields.append("TargetedAdvertisingOptOut") }
      if !withoutGpc.contains(id) { fields.append("Gpc") }
      return (id, (prefix, fields))
    })
  }()

  static var signalKeys: [String] {
    var keys = ["IABTCF_gdprApplies", "IABGPP_TCFEU2_gdprApplies", "IABTCF_AddtlConsent",
                "IABGPP_GppSID", "IABGPP_HDR_GppString", "IABUSPrivacy_String", "IABGPP_USP1_OptOut"]
    for (prefix, fields) in usSections.values {
      keys += fields.map { "IABGPP_\(prefix)_\($0)" }
    }
    return keys
  }

  static func evaluate(resolved: Bool, status: MetaCMPStatus, values: [String: Any],
                       attAuthorized: Bool) -> MetaPermission {
    guard resolved, status == .notRequired || status == .obtained,
          let sections = sectionIDs(values["IABGPP_GppSID"]) else { return .denied }
    if let header = values["IABGPP_HDR_GppString"] {
      guard let string = header as? String, !string.isEmpty,
            string.range(of: "^[A-Za-z0-9_~.\\-]+$", options: .regularExpression) != nil,
            values["IABGPP_GppSID"] != nil else { return .denied }
    }
    guard sections.allSatisfy({ $0 == 2 || $0 == 6 || usSections[$0] != nil }) else { return .denied }

    var applicability: [Int] = []
    for key in ["IABTCF_gdprApplies", "IABGPP_TCFEU2_gdprApplies"] {
      if let value = values[key] {
        guard let number = integer(value), number == 0 || number == 1 else { return .denied }
        applicability.append(number)
      }
    }
    if sections.contains(2) { applicability.append(1) }
    guard Set(applicability).count <= 1 else { return .denied }
    let gdpr = applicability.first
    if gdpr == 1 {
      guard status == .obtained, additionalConsent(values["IABTCF_AddtlConsent"]) == true else { return .denied }
    } else {
      // A malformed/stale explicit provider rejection cannot be overridden by
      // the non-required result. With no AC signal, native UMP is authoritative.
      if let ac = values["IABTCF_AddtlConsent"], additionalConsent(ac) != true { return .denied }
      guard status == .notRequired || (gdpr == 0 && !sections.isEmpty) else { return .denied }
    }

    for section in sections {
      if section == 6 {
        guard integer(values["IABGPP_USP1_OptOut"]) == 2 else { return .denied }
      } else if let (prefix, fields) = usSections[section] {
        for field in fields {
          let value = values["IABGPP_\(prefix)_\(field)"]
          if field == "Gpc" {
            guard integer(value) == 0 else { return .denied }
          } else {
            // IAB: 0 = not applicable, 1 = opted out, 2 = did not opt out.
            guard let choice = integer(value), choice == 0 || choice == 2 else { return .denied }
          }
        }
      }
    }
    if let value = values["IABUSPrivacy_String"] {
      guard let usp = value as? String,
            usp.range(of: "^1[YN-]{3}$", options: .regularExpression) != nil,
            usp == "1---" || Array(usp)[2] == "N" else { return .denied }
    }
    return MetaPermission(collection: true, advertiserID: attAuthorized)
  }

  private static func integer(_ value: Any?) -> Int? {
    if let string = value as? String {
      guard string.range(of: "^[0-9]+$", options: .regularExpression) != nil else { return nil }
      return Int(string)
    }
    if let number = value as? NSNumber {
      let integer = number.intValue
      return number.doubleValue == Double(integer) ? integer : nil
    }
    return nil
  }

  private static func sectionIDs(_ value: Any?) -> Set<Int>? {
    guard let value else { return [] }
    if let string = value as? String {
      if string == "-1" { return [] }
      let parts = string.split(separator: "_", omittingEmptySubsequences: false)
      // IAB specifies underscore separators for GppSID storage.
      let ids = parts.compactMap { integer(String($0)) }
      guard !ids.isEmpty, ids.count == parts.count, ids.allSatisfy({ $0 > 0 }) else { return nil }
      return Set(ids)
    }
    if let numbers = value as? [Int], !numbers.isEmpty, numbers.allSatisfy({ $0 > 0 }) { return Set(numbers) }
    return nil
  }

  private static func additionalConsent(_ value: Any?) -> Bool? {
    guard let string = value as? String else { return nil }
    let parts = string.split(separator: "~", omittingEmptySubsequences: false).map(String.init)
    guard (parts.count == 2 && parts[0] == "1") || (parts.count == 3 && parts[0] == "2") else { return nil }
    func ids(_ text: String) -> [Int]? {
      if text.isEmpty { return [] }
      let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
      let numbers = pieces.compactMap { integer(String($0)) }
      guard pieces.count == numbers.count, numbers.allSatisfy({ $0 > 0 }) else { return nil }
      return numbers
    }
    guard let consented = ids(parts[1]) else { return nil }
    if parts.count == 3 {
      guard parts[2] == "dv" || (parts[2].hasPrefix("dv.") && ids(String(parts[2].dropFirst(3))) != nil) else { return nil }
    }
    return consented.contains(89)
  }
}

protocol MetaAppEventsSDK: AnyObject {
  func initialize(advertiserID: Bool)
  func resume(advertiserID: Bool)
  func suspend()
  func activate()
  func log(name: String)
}

/// Main-thread lifecycle. An epoch ends only at didEnterBackground, not when
/// ATT/CMP/system UI temporarily makes the app inactive.
final class MetaAppEventsLifecycle {
  private let sdk: MetaAppEventsSDK
  private let permission: (Bool) -> MetaPermission
  private let isForeground: () -> Bool
  private var resolved = false
  private var initialized = false
  private var activatedThisEpoch = false

  static let events = ["onboardingCompleted": "fb_mobile_tutorial_completion",
                       "raceJoined": "bara_race_joined", "shopViewed": "bara_shop_viewed",
                       "membershipViewed": "bara_membership_viewed", "coinOffersViewed": "bara_coin_offers_viewed",
                       "purchaseIntent": "bara_purchase_intent"]

  init(sdk: MetaAppEventsSDK, permission: @escaping (Bool) -> MetaPermission,
       isForeground: @escaping () -> Bool) {
    self.sdk = sdk; self.permission = permission; self.isForeground = isForeground
  }
  func updateConsent(resolved: Bool) { self.resolved = resolved; _ = refresh() }
  func becameActive() { _ = refresh() }
  func enteredBackground() { activatedThisEpoch = false }

  @discardableResult func log(event: String) -> Bool {
    guard let name = Self.events[event], refresh() else { return false }
    sdk.log(name: name)
    return true
  }

  private func refresh() -> Bool {
    let decision = permission(resolved)
    guard decision.collection else {
      if initialized { sdk.suspend() }
      return false
    }
    guard isForeground() else { return false }
    if !initialized {
      sdk.initialize(advertiserID: decision.advertiserID)
      initialized = true
    }
    sdk.resume(advertiserID: decision.advertiserID)
    if !activatedThisEpoch {
      // No dispatch/await between SDK initialization and first activation.
      sdk.activate()
      activatedThisEpoch = true
    }
    return true
  }
}
