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
    guard sections.allSatisfy({ $0 == 2 || $0 == 6 || usSections[$0] != nil }) else { return .denied }
    var decoded: [String: Int] = [:]
    if let header = values["IABGPP_HDR_GppString"] {
      guard let string = header as? String, values["IABGPP_GppSID"] != nil,
            let fields = MetaGPP.decode(string, applicable: sections) else { return .denied }
      decoded = fields
      // Never allow the encoded signal to conceal an explicit expanded denial
      // or vice versa. UMP itself supplies only the two compact GPP keys.
      for (key, value) in decoded {
        if let expanded = values[key], integer(expanded) != value { return .denied }
      }
    }

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
      // An obtained US message need not populate the separate European TCF
      // applicability key. Its applicable US sections still require evaluation.
      guard status == .notRequired || (!sections.isEmpty && !sections.contains(2)) else { return .denied }
    }

    for section in sections {
      if section == 6 {
        guard decoded["IABGPP_USP1_OptOut"] ?? integer(values["IABGPP_USP1_OptOut"]) == 2 else { return .denied }
      } else if let (prefix, fields) = usSections[section] {
        for field in fields {
          let key = "IABGPP_\(prefix)_\(field)"
          let value: Any? = decoded[key] ?? values[key]
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

/// Bounded reader for IAB GPP headers and the US sections used by this policy.
/// Format reference and independently encoded fixtures: docs/meta-gpp-fix-validation.md.
/// This only decodes CMP data in memory; it never creates or changes consent.
private enum MetaGPP {
  private enum Invalid: Error { case signal }

  static func decode(_ string: String, applicable: Set<Int>) -> [String: Int]? {
    do { return try read(string, applicable: applicable) } catch { return nil }
  }

  private static func read(_ string: String, applicable: Set<Int>) throws -> [String: Int] {
    guard !string.isEmpty, string.utf8.count <= 16384,
          string.range(of: "^[A-Za-z0-9_~.\\-]+$", options: .regularExpression) != nil else { throw Invalid.signal }
    let parts = string.split(separator: "~", omittingEmptySubsequences: false).map(String.init)
    guard let first = parts.first, parts.count <= 65, parts.allSatisfy({ !$0.isEmpty }) else { throw Invalid.signal }
    var header = try Bits(first)
    guard try header.take(6) == 3, try header.take(6) == 1 else { throw Invalid.signal }
    let count = try header.take(12)
    guard count <= 64 else { throw Invalid.signal }
    var ids: [Int] = []
    var last = 0
    for _ in 0..<count {
      let range = try header.take(1) == 1
      let start = try last + header.fibonacci()
      let end = range ? try start + header.fibonacci() : start
      guard start > last, end <= 1024, ids.count + end - start + 1 <= 64 else { throw Invalid.signal }
      ids.append(contentsOf: start...end)
      last = end
    }
    guard header.validPadding(), ids.count == parts.count - 1,
          applicable.isSubset(of: Set(ids)) else { throw Invalid.signal }
    var result: [String: Int] = [:]
    for (index, id) in ids.enumerated() where applicable.contains(id) {
      if id == 6 {
        let usp = Array(parts[index + 1])
        guard usp.count == 4, usp[0] == "1", usp.dropFirst().allSatisfy({ "YN-".contains($0) }),
              usp[2] == "N" || usp[2] == "Y" else { throw Invalid.signal }
        result["IABGPP_USP1_OptOut"] = usp[2] == "N" ? 2 : 1
      } else if let (prefix, fields) = MetaAppEventsPolicy.usSections[id] {
        let choices = try us(parts[index + 1], id: id, hasGpc: fields.contains("Gpc"))
        for (field, value) in choices { result["IABGPP_\(prefix)_\(field)"] = value }
      }
    }
    return result
  }

  // Number of two-bit core fields after the version, sale offset, and MSPA
  // covered-transaction offset. Arrays occupy one field per element.
  private static let layouts: [Int: (count: Int, sale: Int, mspa: Int)] = [
    7: (32, 6, 29), 8: (20, 3, 17), 9: (17, 3, 14), 10: (16, 3, 13),
    11: (18, 4, 15), 12: (19, 3, 16), 13: (20, 3, 17), 14: (20, 3, 17),
    15: (23, 3, 20), 16: (18, 3, 15), 17: (23, 3, 20), 18: (18, 4, 15),
    19: (18, 3, 15), 20: (20, 3, 17), 21: (24, 3, 21), 22: (18, 3, 15),
    23: (18, 3, 15), 24: (8, 5, 0), 25: (9, 5, 0), 26: (9, 5, 0), 27: (9, 5, 0)
  ]

  private static func us(_ encoded: String, id: Int, hasGpc: Bool) throws -> [String: Int] {
    let segments = encoded.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    let hasSensitiveSegment = (25...27).contains(id)
    guard let first = segments.first, var layout = layouts[id],
          segments.count <= (hasGpc || hasSensitiveSegment ? 2 : 1) else { throw Invalid.signal }
    var core = try Bits(first)
    let version = try core.take(6)
    guard version == 1 || (id == 7 && version == 2) else { throw Invalid.signal }
    if id == 7 && version == 1 { layout = (27, 6, 24) }
    var values: [Int] = []
    for _ in 0..<layout.count {
      let value = try core.take(2)
      guard value <= 2 else { throw Invalid.signal }
      values.append(value)
    }
    guard values[layout.mspa] != 0, core.validPadding() else { throw Invalid.signal }
    var result = ["SaleOptOut": values[layout.sale]]
    if id == 7 || id == 8 { result["SharingOptOut"] = values[layout.sale + 1] }
    if id != 8 { result["TargetedAdvertisingOptOut"] = values[layout.sale + (id == 7 ? 2 : 1)] }
    if hasGpc {
      // The optional GPC segment's absence means no GPC signal was supplied,
      // not malformed consent. Explicit GPC=true always blocks collection.
      result["Gpc"] = 0
      if segments.count == 2 {
        var gpc = try Bits(segments[1])
        guard try gpc.take(2) == 1 else { throw Invalid.signal }
        result["Gpc"] = try gpc.take(1)
        guard gpc.validPadding() else { throw Invalid.signal }
      }
    }
    if hasSensitiveSegment && segments.count == 2 {
      // IN/KY/RI define an optional eight-choice sensitive-data segment, not
      // a GPC segment. Validate its shape without changing Bara's data scope.
      var sensitive = try Bits(segments[1])
      for _ in 0..<8 { guard try sensitive.take(2) <= 2 else { throw Invalid.signal } }
      guard sensitive.validPadding() else { throw Invalid.signal }
    }
    return result
  }

  private struct Bits {
    private let bits: [Int]
    private var position = 0
    init(_ string: String) throws {
      let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_".utf8)
      guard !string.isEmpty, string.utf8.count <= 4096 else { throw Invalid.signal }
      var bits: [Int] = []
      for character in string.utf8 {
        guard let value = alphabet.firstIndex(of: character) else { throw Invalid.signal }
        for shift in stride(from: 5, through: 0, by: -1) { bits.append((value >> shift) & 1) }
      }
      self.bits = bits
    }
    mutating func take(_ count: Int) throws -> Int {
      guard position + count <= bits.count else { throw Invalid.signal }
      var result = 0
      for _ in 0..<count { result = (result << 1) | bits[position]; position += 1 }
      return result
    }
    mutating func fibonacci() throws -> Int {
      var previous = 0, current = 1, next = 2, result = 0
      for _ in 0..<20 {
        let bit = try take(1)
        if bit == 1 && previous == 1 { return result }
        if bit == 1 { result += current }
        (current, next) = (next, current + next)
        previous = bit
      }
      throw Invalid.signal
    }
    func validPadding() -> Bool {
      // Accept both spec six-bit padding and the IAB encoder's byte-then-six
      // padding. Reject excess characters and nonzero trailing bits.
      let simple = ((position + 5) / 6) * 6
      let bytes = ((((position + 7) / 8) * 8 + 5) / 6) * 6
      return (bits.count == simple || bits.count == bytes) && bits[position...].allSatisfy({ $0 == 0 })
    }
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
