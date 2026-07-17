//
//  ProStore.swift
//  SuStash
//
//  StoreKit 2 entitlement + purchase state for SuStash Pro.
//  Pro gates: iCloud sync, accent theme customization, JSON export.
//

import Foundation
import OSLog
import StoreKit

@MainActor
@Observable
final class ProStore {
    static let shared = ProStore()

    static let monthlyID = "com.atealab.SuStash.pro.monthly"
    static let yearlyID = "com.atealab.SuStash.pro.yearly"
    static let lifetimeID = "com.atealab.SuStash.pro.lifetime"
    private static let productIDs: Set<String> = [monthlyID, yearlyID, lifetimeID]

    private static let cachedProKey = "isProCached"
    private let logger = Logger(subsystem: "com.atealab.SuStash", category: "ProStore")

    private(set) var products: [Product] = []
    /// True once the first product fetch finished (even empty) — lets the
    /// paywall show a retry state instead of an eternal spinner.
    private(set) var didFinishLoadingProducts = false
    private(set) var isPro: Bool
    private(set) var lastPurchaseError: String?
    private var updatesTask: Task<Void, Never>?

    private init() {
        // Last verified state, so Pro features don't flicker off while
        // StoreKit wakes up (or the device is offline).
        isPro = AppSettings.store.bool(forKey: Self.cachedProKey)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-pro") {
            isPro = true
        }
        #endif
    }

    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task {
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await refreshEntitlements()
            }
        }
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    func loadProducts() async {
        do {
            products = try await Product.products(for: Self.productIDs)
                .sorted { $0.price < $1.price }
        } catch {
            logger.error("Product load failed: \(error)")
        }
        didFinishLoadingProducts = true
    }

    func purchase(_ product: Product) async -> Bool {
        lastPurchaseError = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                }
                await refreshEntitlements()
                return isPro
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            lastPurchaseError = error.localizedDescription
            logger.error("Purchase failed: \(error)")
            return false
        }
    }

    func restorePurchases() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }

    private func refreshEntitlements() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-pro") { return }
        #endif
        var pro = false
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement,
               Self.productIDs.contains(transaction.productID) {
                pro = true
                break
            }
        }
        isPro = pro
        AppSettings.store.set(pro, forKey: Self.cachedProKey)
    }
}
