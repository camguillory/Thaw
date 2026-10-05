//
//  OwnerScopedPositionStoreTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("Position writes stay on the item's own key")
struct OwnerScopedPositionStoreTests {
    private static func item(_ bundleID: String, _ title: String, windowID: CGWindowID, x: CGFloat) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string(bundleID), title: title, instanceIndex: 0),
            windowID: windowID,
            ownerPID: pid_t(windowID),
            sourcePID: pid_t(windowID),
            bounds: CGRect(x: x, y: 3.5, width: 24, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    /// The first item has no key of its own and resolves to another owner's same-named key.
    private static func bar() -> (items: [MenuBarItem], base: FakeStore) {
        let stray = item("com.example.meters", "Item-1", windowID: 1, x: 100)
        let neighbour = item("com.example.meters", "Item-2", windowID: 2, x: 130)
        let base = FakeStore(keys: [
            stray.uniqueIdentifier: "status:com.example.printer::Item-1",
            neighbour.uniqueIdentifier: "status:com.example.meters::Item-2",
        ])
        return ([stray, neighbour], base)
    }

    @Test("A positional name never takes another app's key")
    func foreignPositionalKeyIsRefused() {
        let (items, base) = Self.bar()
        let store = OwnerScopedPositionStore(wrapping: base)
        #expect(store.resolveKey(for: items[0], existingKeys: base.allKeys, positions: [:], liveItems: items) == nil)
        #expect(!store.move(item: items[0], to: .rightOfItem(items[1]), liveItems: items, experimentalSystemItemHiding: false))
        #expect(base.movedItems.isEmpty)
    }

    @Test("The live-text placeholder never takes another app's key")
    func foreignPlaceholderKeyIsRefused() {
        // Two apps with live-text titles both canonicalize to the placeholder.
        let badge = Self.item("com.example.editor", MenuBarItemTag.volatileTitlePlaceholder, windowID: 4, x: 100)
        let base = FakeStore(keys: [badge.uniqueIdentifier: "status:com.example.meetings::Item"])
        let store = OwnerScopedPositionStore(wrapping: base)
        #expect(store.resolveKey(for: badge, existingKeys: base.allKeys, positions: [:], liveItems: [badge]) == nil)
        #expect(!store.move(item: badge, to: .leftOfItem(badge), liveItems: [badge], experimentalSystemItemHiding: false))
        #expect(base.movedItems.isEmpty)
    }

    @Test("Own keys, titled aliases and display-name owners pass through")
    func legitimateKeysPassThrough() {
        let (items, base) = Self.bar()
        let store = OwnerScopedPositionStore(wrapping: base)
        #expect(store.resolveKey(for: items[1], existingKeys: base.allKeys, positions: [:], liveItems: items)
            == "status:com.example.meters::Item-2")
        #expect(!store.isForeignGenericKey("status:com.example.main::CPU", for: Self.item("com.example.helper", "CPU", windowID: 3, x: 0)))
        #expect(!store.isForeignGenericKey("status:Meters::Item-1", for: items[0]))
    }

    @Test("Bulk writes leave a foreign-keyed item out")
    func applyOrderDropsForeignItem() {
        let (items, base) = Self.bar()
        let store = OwnerScopedPositionStore(wrapping: base)
        _ = store.applyOrder(desiredOrder: items.map(\.uniqueIdentifier), liveItems: items, experimentalSystemItemHiding: false)
        #expect(base.appliedOrder == [items[1].uniqueIdentifier])
        #expect(base.appliedLiveItems == [items[1].uniqueIdentifier])
    }
}

@MainActor
private final class FakeStore: MenuBarPositionStoring {
    private let keys: [String: String]
    private(set) var movedItems: [String] = []
    private(set) var appliedOrder: [String] = []
    private(set) var appliedLiveItems: [String] = []

    init(keys: [String: String]) {
        self.keys = keys
    }

    var allKeys: [String] {
        Array(keys.values)
    }

    func currentPositions() -> [String: Int] {
        Dictionary(uniqueKeysWithValues: keys.values.map { ($0, 0) })
    }

    func readPositions() -> [String: Int] {
        currentPositions()
    }

    func resolveKey(for item: MenuBarItem, existingKeys _: [String], positions _: [String: Int], liveItems _: [MenuBarItem]) -> String? {
        keys[item.uniqueIdentifier]
    }

    func parseStatusKey(_ key: String) -> PositionStatusKey? {
        guard key.hasPrefix("status:"), let separator = key.range(of: "::") else { return nil }
        let owner = String(key[key.index(key.startIndex, offsetBy: 7) ..< separator.lowerBound])
        return PositionStatusKey(owner: owner, identifier: String(key[separator.upperBound...]))
    }

    func isParkedWeight(_: Int) -> Bool {
        false
    }

    func move(item: MenuBarItem, to _: MoveDestination, liveItems _: [MenuBarItem], experimentalSystemItemHiding _: Bool) -> Bool {
        movedItems.append(item.uniqueIdentifier)
        return true
    }

    func applyOrder(desiredOrder: [String], liveItems: [MenuBarItem], experimentalSystemItemHiding _: Bool) -> [String] {
        appliedOrder = desiredOrder
        appliedLiveItems = liveItems.map(\.uniqueIdentifier)
        return desiredOrder
    }

    func respaceOrder(desiredOrder _: [String], liveItems _: [MenuBarItem], experimentalSystemItemHiding _: Bool) -> [String] {
        []
    }

    func breakTiedSiblingWeights(liveItems _: [MenuBarItem]) -> [String] {
        []
    }

    func applyControlItemOrder(desiredOrder _: [MenuBarItem], opaqueVisibleKeys _: [String], liveItems _: [MenuBarItem]) -> [String] {
        []
    }

    func writePositions(_: [String: Int]) {}

    func isProvenAbsent(_: String) -> Bool {
        false
    }

    func recordAbsenceEvidence(seen _: Set<String>, blank _: Set<String>) -> Set<String> {
        []
    }

    func resetAbsenceEvidence() {}
}
