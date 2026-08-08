import Foundation

/// When the pack was made, to the month.
///
/// Month precision is deliberate. The day *is* in the encoding and we read it,
/// but only to check the decode (see below); we do not show it. The one machine
/// where another tool's answer is recorded (coconutBattery, 15 Jan 2026) sits
/// three days from ours (12 Jan 2026), and until that is explained a day figure
/// would be claiming precision we cannot defend. A report handed to a Genius Bar
/// or attached to a resale listing does not need the day.
public struct BatteryManufactureMonth: Equatable, Sendable, Codable {
    public let year: Int
    /// 1...12.
    public let month: Int

    /// The year bound is the encoding's own domain, not a preference: `YY` is two
    /// digits counted from 1992, so it cannot express anything outside
    /// 1992...2091, and nothing before the Intel-era gauges is a real Mac pack.
    /// Both ways in go through here, so a value that exists is a value that
    /// passed.
    public init?(year: Int, month: Int) {
        guard (1...12).contains(month), Self.possibleYears.contains(year) else { return nil }
        self.year = year
        self.month = month
    }

    static let possibleYears = 2005...2091

    /// Decoding has to validate too. The synthesized `init(from:)` would walk
    /// straight past the failable initialiser above, so a payload carrying
    /// `"month": 99` would build a value the type says is impossible, and
    /// `label` would then index off the end of the month names. The App Group
    /// file this decodes from is written by us, but "written by us" is not the
    /// same as "cannot be corrupt".
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let year = try container.decode(Int.self, forKey: .year)
        let month = try container.decode(Int.self, forKey: .month)
        // Delegates rather than repeating the rules, so the two ways in cannot
        // drift apart and admit different values.
        guard let decoded = BatteryManufactureMonth(year: year, month: month) else {
            throw DecodingError.dataCorruptedError(
                forKey: .month, in: container,
                debugDescription: "not a month this encoding can express: \(year)-\(month)"
            )
        }
        self = decoded
    }

    /// "January 2026". Locale-independent on purpose: this ends up in a report
    /// handed to strangers, which has to read the same everywhere, and it is the
    /// same choice the rest of `BatteryReport`'s date lines make.
    public var label: String {
        // Both initialisers enforce the range, so this cannot fail; it is
        // written as a lookup rather than a subscript so that a future third
        // way in degrades to a blank month instead of a crash.
        let name = Self.monthNames.indices.contains(month - 1) ? Self.monthNames[month - 1] : ""
        return name.isEmpty ? "\(year)" : "\(name) \(year)"
    }

    private static let monthNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]

    /// Decode the gauge's `ManufactureDate` field, or nil when we cannot stand
    /// behind the answer.
    ///
    /// The field is not the SMBus packing, and it is not a timestamp. It holds
    /// six ASCII digits written least significant first, which read backwards
    /// give `YYMMDD` with `YY` counted from 1992:
    ///
    ///     55186860028979 -> 0x323131303433 -> "211043" -> "340112" -> 2026-01-12
    ///
    /// Established against the 810 machines in the whatcable probe corpus that
    /// carry the field:
    ///
    /// - Read backwards, 810 of 810 parse as a valid date. Read forwards, 115 do.
    ///   A random six-digit string parses 3.7% of the time, so the direction is
    ///   not in question.
    /// - The 1992 offset is pinned from both sides by facts the data cannot fake.
    ///   At 1991, 393 of 688 packs predate the chip in the machine holding them
    ///   by over six months. At 1993, 156 packs are made after the probe that
    ///   read them. At 1992: one, an M2 Pro carrying a 2021 pack with 324 cycles,
    ///   which is what a replacement pack looks like.
    /// - Pack age computed this way predicts cycle count at r = +0.64, with
    ///   median cycles by age running 18, 77, 147, 216, 292, 372 over the first
    ///   six years. Only a real date does that.
    ///
    /// - Parameters:
    ///   - raw: the gauge's `ManufactureDate` value.
    ///   - gaugeName: `AppleSmartBattery.DeviceName`, the fuel gauge part.
    ///   - now: the read time, used to reject a pack made in the future.
    public static func decode(raw: Int?, gaugeName: String, now: Date) -> BatteryManufactureMonth? {
        guard let raw, raw > 0, isKnownEncoding(gaugeName: gaugeName) else { return nil }

        let bytes = withUnsafeBytes(of: UInt64(bitPattern: Int64(raw)).bigEndian) { Array($0) }
        let digits = Array(bytes.drop { $0 == 0 })
        guard digits.count == 6, digits.allSatisfy({ (48...57).contains($0) }) else { return nil }

        let reversed = digits.reversed().map { Int($0) - 48 }
        let year = 1992 + reversed[0] * 10 + reversed[1]
        let month = reversed[2] * 10 + reversed[3]
        let day = reversed[4] * 10 + reversed[5]

        // The day is read only to check the decode, never shown. An encoding we
        // have misread shows up as an impossible day far more often than as an
        // impossible month, so throwing the whole reading away on a bad day is
        // the cheapest integrity check available.
        guard let candidate = BatteryManufactureMonth(year: year, month: month),
              isRealDate(year: year, month: month, day: day),
              candidate.isNotInTheFuture(now: now)
        else { return nil }
        return candidate
    }

    /// Which gauges this encoding is proven on.
    ///
    /// TI's `bq` family covers 798 of the 810 corpus machines and every one of
    /// them decodes into a sane window. The three Apple `A19xx` gauges do too (5
    /// machines). `SN7038`, the gauge in the corpus iPhone, decodes to 2082, so
    /// it is a different format and is excluded rather than guessed at: an
    /// unknown gauge gets no date, not a wrong one.
    ///
    /// The `bq` test is a part-name shape (`bq` then a digit then alphanumerics,
    /// as in `bq40z651` and `bq20z451`), not a bare prefix. A bare prefix would
    /// also admit a gauge called `bq` or `bq-unknown`, which the corpus never
    /// showed us and whose encoding we would therefore be guessing at.
    private static func isKnownEncoding(gaugeName: String) -> Bool {
        let name = gaugeName.lowercased()
        if ["a1953", "a1964", "a1965"].contains(name) { return true }
        guard name.hasPrefix("bq"), name.count >= 6 else { return false }
        let part = name.dropFirst(2)
        guard let first = part.first, first.isASCII, first.isNumber else { return false }
        return part.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    /// No pack is made in the future. Compared at month granularity, so a pack
    /// assembled days ago still reads; there is deliberately no slack beyond
    /// that. Slack here would mean publishing a date we know cannot be true, and
    /// on a clock that is wrong the honest failure is a blank field.
    ///
    /// The floor lives in the initialiser, with the rest of the encoding's
    /// domain.
    private func isNotInTheFuture(now: Date) -> Bool {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .current
        let today = utc.dateComponents([.year, .month], from: now)
        guard let nowYear = today.year, let nowMonth = today.month else { return false }
        return (year * 12 + month) <= (nowYear * 12 + nowMonth)
    }

    private static func isRealDate(year: Int, month: Int, day: Int) -> Bool {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .current
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return utc.date(from: components) != nil && components.isValidDate(in: utc)
    }
}
