import Foundation

/// Everything the battery publishes, as plain dictionaries: the
/// `AppleSmartBattery` node and, on macOS 27 and later, its registry children.
///
/// Apple moves keys between these places across OS releases. macOS 27 moved
/// most of the node's figures onto `AppleSmartBatteryPack` and its banks, and
/// changed a unit on the way, so fields are looked up across the whole tree by
/// `BatteryFieldResolver` rather than read from one fixed path.
public struct BatteryTree {
    public enum Node: String, CaseIterable, Sendable {
        case battery
        case pack
        case bank

        /// Registry distance from the battery node. Part of what "nearest the
        /// root" means when the resolver has to search.
        var depth: Int {
            switch self {
            case .battery: return 0
            case .pack: return 1
            case .bank: return 2
            }
        }
    }

    /// The `AppleSmartBattery` node's properties. Over the iDevice relay this is
    /// the whole reply. On a Mac it holds only the keys the reader asked for by
    /// name, because listing the node's keys needs the bulk read that can crash
    /// (WhatCable #181).
    public let battery: [String: Any]
    /// The `AppleSmartBatteryPack` child's properties, nil where there is none.
    public let pack: [String: Any]?
    /// Each `AppleSmartBatteryBank` child's properties.
    public let banks: [[String: Any]]

    public init(battery: [String: Any], pack: [String: Any]? = nil, banks: [[String: Any]] = []) {
        self.battery = battery
        self.pack = pack
        self.banks = banks
    }

    /// The dictionaries of one node kind: one for the battery, zero or one for
    /// the pack, one per bank.
    func dictionaries(of node: Node) -> [[String: Any]] {
        switch node {
        case .battery: return [battery]
        case .pack: return pack.map { [$0] } ?? []
        case .bank: return banks
        }
    }
}
