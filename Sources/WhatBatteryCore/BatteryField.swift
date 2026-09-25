import Foundation

/// One place a field can live: a node in the battery tree and the key path
/// down from that node's properties, ending with the field's own key.
public struct FieldLocation: Equatable, Sendable, CustomStringConvertible {
    public let node: BatteryTree.Node
    public let path: [String]

    public init(_ node: BatteryTree.Node, _ path: [String]) {
        self.node = node
        self.path = path
    }

    public var description: String {
        "\(node.rawValue):" + path.joined(separator: ".")
    }
}

/// A battery figure and everywhere it is known to live, in preference order.
public struct BatteryField<Value: Equatable> {
    public let key: String
    public let locations: [FieldLocation]
    /// Look anywhere in the tree when no known location has it. Only for
    /// fields whose meaning cannot change with where they sit (counts, dates,
    /// serials). Never for anything with a unit or a shape: a temperature
    /// found somewhere new may be in a different unit, and showing it would
    /// turn "missing" into "wrong".
    public let searchAnywhere: Bool
    /// The field's value from a raw property, or nil when the raw value is
    /// missing, empty, zero or implausible. Nil moves the lookup on to the next
    /// place: WhatCable once let an empty value hide the real one because
    /// Swift's `??` only falls through on nil. Takes the location so
    /// a field whose unit differs by location can convert accordingly.
    public let decode: (Any, FieldLocation) -> Value?

    public init(
        key: String,
        locations: [FieldLocation],
        searchAnywhere: Bool,
        decode: @escaping (Any, FieldLocation) -> Value?
    ) {
        self.key = key
        self.locations = locations
        self.searchAnywhere = searchAnywhere
        self.decode = decode
    }
}

/// What the resolver found: the value, where, and whether the whole-tree
/// search supplied it rather than a known location.
public struct FieldResolution<Value> {
    public let value: Value?
    public let location: FieldLocation?
    public let foundBySearch: Bool

    static var missing: FieldResolution<Value> {
        FieldResolution(value: nil, location: nil, foundBySearch: false)
    }
}

public enum BatteryFieldResolver {
    public static func resolve<Value>(_ field: BatteryField<Value>, in tree: BatteryTree) -> FieldResolution<Value> {
        for location in field.locations {
            if let value = agreedValue(field, at: location, in: tree) {
                return FieldResolution(value: value, location: location, foundBySearch: false)
            }
        }
        guard field.searchAnywhere else { return .missing }
        return search(field, in: tree)
    }

    /// The field's value at one known location. Where the location names a
    /// node kind with several nodes (banks), every node that has a value must
    /// agree, or the location counts as not having one.
    private static func agreedValue<Value>(
        _ field: BatteryField<Value>,
        at location: FieldLocation,
        in tree: BatteryTree
    ) -> Value? {
        let values = tree.dictionaries(of: location.node).compactMap { dictionary in
            raw(at: location.path, in: dictionary).flatMap { field.decode($0, location) }
        }
        guard let first = values.first, values.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    private static func raw(at path: [String], in dictionary: [String: Any]) -> Any? {
        guard let head = path.first else { return nil }
        guard path.count > 1 else { return dictionary[head] }
        guard let child = dictionary[head] as? [String: Any] else { return nil }
        return raw(at: Array(path.dropFirst()), in: child)
    }

    private struct Hit<Value> {
        let depth: Int
        let location: FieldLocation
        let value: Value
    }

    /// Every place in the tree holding the field's key with a value the field
    /// accepts. The hit nearest the battery node wins, counting both registry
    /// distance and how far down the node's dictionaries the key sits. Hits
    /// at that depth that disagree give nothing rather than a guess.
    private static func search<Value>(_ field: BatteryField<Value>, in tree: BatteryTree) -> FieldResolution<Value> {
        var hits: [Hit<Value>] = []
        for node in BatteryTree.Node.allCases {
            for dictionary in tree.dictionaries(of: node) {
                collect(field, in: dictionary, node: node, path: [], into: &hits)
            }
        }
        guard let nearest = hits.map(\.depth).min() else { return .missing }
        // Sorted so the reported location does not depend on dictionary order.
        let closest = hits
            .filter { $0.depth == nearest }
            .sorted { $0.location.description < $1.location.description }
        guard let first = closest.first, closest.allSatisfy({ $0.value == first.value }) else { return .missing }
        return FieldResolution(value: first.value, location: first.location, foundBySearch: true)
    }

    private static func collect<Value>(
        _ field: BatteryField<Value>,
        in dictionary: [String: Any],
        node: BatteryTree.Node,
        path: [String],
        into hits: inout [Hit<Value>]
    ) {
        for (key, raw) in dictionary {
            let here = path + [key]
            if key == field.key {
                let location = FieldLocation(node, here)
                if let value = field.decode(raw, location) {
                    hits.append(Hit(depth: node.depth + here.count, location: location, value: value))
                }
            }
            if let child = raw as? [String: Any] {
                collect(field, in: child, node: node, path: here, into: &hits)
            }
        }
    }
}
