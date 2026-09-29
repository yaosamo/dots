import AppKit
import StoreKit

/// What Dots Pro unlocks. Every dot stays free to switch on; these are the parts inside them.
enum ProFeature: CaseIterable {
    case cameraEffects, brushes, whiteboard, clipboardHistory

    var title: String {
        switch self {
        case .cameraEffects: "Camera effects"
        case .brushes: "Shader brushes"
        case .whiteboard: "Whiteboard"
        case .clipboardHistory: "Full clipboard history"
        }
    }

    var detail: String {
        switch self {
        case .cameraEffects: "Electric, fire, rainbow and cloud around your bubble."
        case .brushes: "Draw with electric, fire and rainbow ink."
        case .whiteboard: "A board with shapes, arrows and text that's still there tomorrow."
        case .clipboardHistory: "Your last five copies instead of three."
        }
    }

    var symbol: String {
        switch self {
        case .cameraEffects: "sparkles"
        case .brushes: "flame.fill"
        case .whiteboard: "rectangle.on.rectangle"
        case .clipboardHistory: "doc.on.clipboard"
        }
    }
}

/// The one-time Dots Pro purchase (a non-consumable in-app purchase).
/// `isPro` is cached so Dots launches unlocked straight away; StoreKit confirms it at launch and
/// whenever a transaction changes (a purchase elsewhere, Family Sharing, a refund).
@MainActor
final class ProStore: ObservableObject {
    static let shared = ProStore()
    static let productID = "app.dots.Dots.pro"
    private static let cacheKey = "pro.unlocked"
    /// The number of clipboard copies shown without Pro.
    static let freeClipboardLimit = 3

    enum PurchaseState: Equatable {
        case idle, purchasing, pending, failed(String)
    }

    @Published private var isEntitled = UserDefaults.standard.bool(forKey: cacheKey) {
        didSet { UserDefaults.standard.set(isEntitled, forKey: Self.cacheKey) }
    }
    @Published private(set) var product: Product?
    @Published private(set) var purchaseState = PurchaseState.idle

    #if DEBUG
    /// "Pretend Pro" in the menu bar menu, to try both states without StoreKit.
    @Published var debugOverride: Bool? = nil
    var isPro: Bool { debugOverride ?? isEntitled }
    #else
    var isPro: Bool { isEntitled }
    #endif

    private var updates: Task<Void, Never>?

    private init() {}

    func start() {
        guard updates == nil else { return }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result { await transaction.finish() }
                await self?.refreshEntitlement()
            }
        }
        Task {
            await loadProduct()
            await refreshEntitlement()
        }
    }

    func loadProduct() async {
        guard product == nil else { return }
        product = try? await Product.products(for: [Self.productID]).first
    }

    /// Only verified, unrevoked transactions count.
    func refreshEntitlement() async {
        var entitled = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                entitled = true
            }
        }
        isEntitled = entitled
    }

    func purchase() async {
        await loadProduct()
        guard let product else {
            purchaseState = .failed("Dots Pro isn't available right now. Try again in a moment.")
            return
        }
        // Dots is an accessory app in non-activating panels; the purchase sheet needs it active.
        NSApp.activate()
        purchaseState = .purchasing
        do {
            switch try await product.purchase() {
            case .success(let result):
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await refreshEntitlement()
                    purchaseState = .idle
                } else {
                    purchaseState = .failed("The App Store couldn't verify the purchase.")
                }
            case .pending:
                // Ask to Buy or a payment that needs approval: `Transaction.updates` finishes it.
                purchaseState = .pending
            case .userCancelled:
                purchaseState = .idle
            @unknown default:
                purchaseState = .idle
            }
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }

    func restore() async {
        purchaseState = .purchasing
        try? await AppStore.sync()
        await refreshEntitlement()
        purchaseState = isEntitled ? .idle : .failed("No Dots Pro purchase was found for this Apple Account.")
    }

    func resetPurchaseState() {
        if purchaseState != .purchasing { purchaseState = .idle }
    }
}
