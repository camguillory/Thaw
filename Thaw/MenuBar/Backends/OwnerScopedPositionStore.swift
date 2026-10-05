//
//  OwnerScopedPositionStore.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// A position store that never gives an item with a generic name another app's key.
///
/// When an item's own key is absent, resolution can fall back to a key with the same title
/// under another owner. A positional name (Item-N) or the placeholder for live-text titles
/// (Item) never names the same icon across apps, so a write would move another app's item.
/// Such items resolve to no key: a move that names one is declined, so the caller drags
/// instead, and every write leaves them out of the live set.
@MainActor
struct OwnerScopedPositionStore: MenuBarPositionStoring {
    private static let diagLog = DiagLog(category: "OwnerScopedPositionStore")

    private let base: any MenuBarPositionStoring

    init(wrapping base: any MenuBarPositionStoring) {
        self.base = base
    }

    /// Whether key belongs to an owner other than item's while item carries a generic name.
    func isForeignGenericKey(_ key: String, for item: MenuBarItem) -> Bool {
        let title = item.tag.title
        guard title == MenuBarItemTag.volatileTitlePlaceholder || title.wholeMatch(of: /Item-\d+/) != nil,
              case let .string(bundleID) = item.tag.namespace,
              let owner = base.parseStatusKey(key)?.owner
        else { return false }
        // ponytail: an owner without a dot may be this app's display name, so only
        // bundle-shaped owners are compared; match display names too if one slips through.
        return owner != bundleID && owner.contains(".")
    }

    /// Whether item would resolve to another app's key among liveItems.
    private func resolvesForeign(_ item: MenuBarItem, among liveItems: [MenuBarItem], positions: [String: Int]) -> Bool {
        guard let key = base.resolveKey(
            for: item,
            existingKeys: Array(positions.keys),
            positions: positions,
            liveItems: liveItems
        ), isForeignGenericKey(key, for: item) else { return false }
        Self.diagLog.debug("leaving \(item.logString) out of position writes: \(key) belongs to another app")
        return true
    }

    /// liveItems without the items that would resolve to another app's key.
    private func ownedItems(_ liveItems: [MenuBarItem]) -> [MenuBarItem] {
        let positions = base.currentPositions()
        return liveItems.filter { !resolvesForeign($0, among: liveItems, positions: positions) }
    }

    private func ownedOrder(_ desiredOrder: [String], among owned: [MenuBarItem], of liveItems: [MenuBarItem]) -> [String] {
        let dropped = Set(liveItems.map(\.uniqueIdentifier)).subtracting(owned.map(\.uniqueIdentifier))
        return dropped.isEmpty ? desiredOrder : desiredOrder.filter { !dropped.contains($0) }
    }

    // MARK: Reading

    func currentPositions() -> [String: Int] {
        base.currentPositions()
    }

    func readPositions() -> [String: Int] {
        base.readPositions()
    }

    func positionsDomainIsAccessible() -> Bool {
        base.positionsDomainIsAccessible()
    }

    func resolveKey(
        for item: MenuBarItem,
        existingKeys: [String],
        positions: [String: Int],
        liveItems: [MenuBarItem]
    ) -> String? {
        let key = base.resolveKey(
            for: item,
            existingKeys: existingKeys,
            positions: positions,
            liveItems: liveItems
        )
        return key.flatMap { isForeignGenericKey($0, for: item) ? nil : $0 }
    }

    func parseStatusKey(_ key: String) -> PositionStatusKey? {
        base.parseStatusKey(key)
    }

    func isParkedWeight(_ weight: Int) -> Bool {
        base.isParkedWeight(weight)
    }

    // MARK: Writing, scoped to owned keys

    @discardableResult
    func move(
        item: MenuBarItem,
        to destination: MoveDestination,
        liveItems: [MenuBarItem],
        experimentalSystemItemHiding: Bool
    ) -> Bool {
        move(
            item: item,
            to: destination,
            liveItems: liveItems,
            experimentalSystemItemHiding: experimentalSystemItemHiding,
            mayRewriteAroundUnplaceableItems: false
        )
    }

    @discardableResult
    func move(
        item: MenuBarItem,
        to destination: MoveDestination,
        liveItems: [MenuBarItem],
        experimentalSystemItemHiding: Bool,
        mayRewriteAroundUnplaceableItems: Bool
    ) -> Bool {
        let positions = base.currentPositions()
        guard ![item, destination.targetItem].contains(where: {
            resolvesForeign($0, among: liveItems, positions: positions)
        }) else { return false }
        let owned = ownedItems(liveItems)
        return base.move(
            item: item,
            to: destination,
            liveItems: owned,
            experimentalSystemItemHiding: experimentalSystemItemHiding,
            mayRewriteAroundUnplaceableItems: mayRewriteAroundUnplaceableItems
        )
    }

    func applyOrder(
        desiredOrder: [String],
        liveItems: [MenuBarItem],
        experimentalSystemItemHiding: Bool
    ) -> [String] {
        applyOrder(
            desiredOrder: desiredOrder,
            liveItems: liveItems,
            experimentalSystemItemHiding: experimentalSystemItemHiding,
            mayRewriteAroundUnplaceableItems: false
        )
    }

    func applyOrder(
        desiredOrder: [String],
        liveItems: [MenuBarItem],
        experimentalSystemItemHiding: Bool,
        mayRewriteAroundUnplaceableItems: Bool
    ) -> [String] {
        let owned = ownedItems(liveItems)
        return base.applyOrder(
            desiredOrder: ownedOrder(desiredOrder, among: owned, of: liveItems),
            liveItems: owned,
            experimentalSystemItemHiding: experimentalSystemItemHiding,
            mayRewriteAroundUnplaceableItems: mayRewriteAroundUnplaceableItems
        )
    }

    func respaceOrder(
        desiredOrder: [String],
        liveItems: [MenuBarItem],
        experimentalSystemItemHiding: Bool
    ) -> [String] {
        respaceOrder(
            desiredOrder: desiredOrder,
            liveItems: liveItems,
            experimentalSystemItemHiding: experimentalSystemItemHiding,
            mayRewriteAroundUnplaceableItems: false
        )
    }

    func respaceOrder(
        desiredOrder: [String],
        liveItems: [MenuBarItem],
        experimentalSystemItemHiding: Bool,
        mayRewriteAroundUnplaceableItems: Bool
    ) -> [String] {
        let owned = ownedItems(liveItems)
        return base.respaceOrder(
            desiredOrder: ownedOrder(desiredOrder, among: owned, of: liveItems),
            liveItems: owned,
            experimentalSystemItemHiding: experimentalSystemItemHiding,
            mayRewriteAroundUnplaceableItems: mayRewriteAroundUnplaceableItems
        )
    }

    func breakTiedSiblingWeights(liveItems: [MenuBarItem]) -> [String] {
        base.breakTiedSiblingWeights(liveItems: ownedItems(liveItems))
    }

    func applyControlItemOrder(
        desiredOrder: [MenuBarItem],
        opaqueVisibleKeys: [String],
        liveItems: [MenuBarItem]
    ) -> [String] {
        let owned = ownedItems(liveItems)
        let ownedIDs = Set(owned.map(\.uniqueIdentifier))
        let liveIDs = Set(liveItems.map(\.uniqueIdentifier))
        return base.applyControlItemOrder(
            desiredOrder: desiredOrder.filter { !liveIDs.contains($0.uniqueIdentifier) || ownedIDs.contains($0.uniqueIdentifier) },
            opaqueVisibleKeys: opaqueVisibleKeys,
            liveItems: owned
        )
    }

    func writePositions(_ positions: [String: Int]) {
        base.writePositions(positions)
    }

    // MARK: Absence ledger

    func isProvenAbsent(_ key: String) -> Bool {
        base.isProvenAbsent(key)
    }

    func recordAbsenceEvidence(seen: Set<String>, blank: Set<String>) -> Set<String> {
        base.recordAbsenceEvidence(seen: seen, blank: blank)
    }

    func resetAbsenceEvidence() {
        base.resetAbsenceEvidence()
    }
}
