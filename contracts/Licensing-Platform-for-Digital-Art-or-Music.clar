(define-non-fungible-token digital-license uint)

(define-constant contract-owner tx-sender)
(define-constant royalty-percentage u5)
(define-constant err-not-owner (err u100))
(define-constant err-already-exists (err u101))
(define-constant err-invalid-license (err u102))
(define-constant err-unauthorized (err u103))
(define-constant err-license-expired (err u104))
(define-constant err-invalid-collaborator (err u105))
(define-constant err-invalid-shares (err u106))
(define-constant err-escrow-not-found (err u107))
(define-constant err-escrow-expired (err u108))
(define-constant err-insufficient-funds (err u109))
(define-constant err-escrow-already-released (err u110))
(define-constant err-invalid-pricing-strategy (err u111))
(define-constant err-pricing-not-active (err u112))

(define-data-var next-license-id uint u1)
(define-data-var next-escrow-id uint u1)
(define-data-var total-licenses uint u0)
(define-data-var next-pricing-id uint u1)

(define-map licenses
    uint 
    {
        creator: principal,
        owner: principal,
        ipfs-hash: (string-ascii 64),
        price: uint,
        created-at: uint,
        usage-type: (string-ascii 20),
        is-transferable: bool,
        expires-at: (optional uint),
        is-renewable: bool,
        is-collaborative: bool
    }
)

(define-map creator-royalties
    principal
    uint
)

(define-map license-usage-history
    uint
    (list 10 {user: principal, timestamp: uint})
)

(define-map license-collaborators
    uint
    (list 5 {collaborator: principal, share-percentage: uint})
)

(define-map collaborator-earnings
    {license-id: uint, collaborator: principal}
    uint
)

(define-map license-escrows
    uint
    {
        buyer: principal,
        seller: principal,
        license-id: uint,
        amount: uint,
        expiry-height: uint,
        released: bool
    }
)

(define-map dynamic-pricing
    uint
    {
        license-id: uint,
        strategy: (string-ascii 10),
        base-price: uint,
        current-price: uint,
        demand-factor: uint,
        price-multiplier: uint,
        last-updated: uint,
        is-active: bool
    }
)

(define-map license-purchase-count
    uint
    uint
)

(define-map pricing-history
    uint
    (list 20 {price: uint, timestamp: uint})
)

(define-read-only (get-license-details (license-id uint))
    (ok (unwrap! (map-get? licenses license-id) err-invalid-license))
)

(define-read-only (get-creator-royalties (creator principal))
    (ok (default-to u0 (map-get? creator-royalties creator)))
)

(define-read-only (get-total-licenses)
    (ok (var-get total-licenses))
)

(define-read-only (get-current-price (license-id uint))
    (let
        (
            (pricing-info (map-get? dynamic-pricing license-id))
            (base-license (unwrap! (map-get? licenses license-id) err-invalid-license))
        )
        (match pricing-info
            some-pricing (if (get is-active some-pricing)
                (ok (get current-price some-pricing))
                (ok (get price base-license)))
            (ok (get price base-license))
        )
    )
)

(define-read-only (get-pricing-details (license-id uint))
    (ok (map-get? dynamic-pricing license-id))
)

(define-read-only (get-license-demand (license-id uint))
    (ok (default-to u0 (map-get? license-purchase-count license-id)))
)

(define-read-only (get-pricing-history (license-id uint))
    (ok (default-to (list) (map-get? pricing-history license-id)))
)

(define-public (create-license-with-expiry (ipfs-hash (string-ascii 64)) (price uint) (usage-type (string-ascii 20)) (transferable bool) (duration-blocks (optional uint)) (renewable bool))
    (let
        (
            (license-id (var-get next-license-id))
            (expiry (if (is-some duration-blocks)
                (some (+ stacks-block-height (unwrap-panic duration-blocks)))
                none))
        )
        (try! (nft-mint? digital-license license-id tx-sender))
        (map-set licenses license-id {
            creator: tx-sender,
            owner: tx-sender,
            ipfs-hash: ipfs-hash,
            price: price,
            created-at: stacks-block-height,
            usage-type: usage-type,
            is-transferable: transferable,
            expires-at: expiry,
            is-renewable: renewable,
            is-collaborative: false
        })
        (var-set next-license-id (+ license-id u1))
        (var-set total-licenses (+ (var-get total-licenses) u1))
        (ok license-id)
    )
)

(define-public (renew-license (license-id uint) (additional-blocks uint))
    (let
        (
            (license (unwrap! (map-get? licenses license-id) err-invalid-license))
            (creator (get creator license))
            (renewal-price (/ (get price license) u2))
            (royalty (/ (* renewal-price royalty-percentage) u100))
        )
        (asserts! (is-eq tx-sender (get owner license)) err-not-owner)
        (asserts! (get is-renewable license) err-unauthorized)
        (try! (stx-transfer? renewal-price tx-sender creator))
        (try! (stx-transfer? royalty tx-sender creator))
        (let
            (
                (current-expiry (default-to stacks-block-height (get expires-at license)))
                (new-expiry (+ current-expiry additional-blocks))
            )
            (map-set licenses license-id (merge license {expires-at: (some new-expiry)}))
        )
        (map-set creator-royalties creator 
            (+ (default-to u0 (map-get? creator-royalties creator)) royalty))
        (ok true)
    )
)

(define-public (transfer-license (license-id uint) (recipient principal))
    (let
        (
            (license (unwrap! (map-get? licenses license-id) err-invalid-license))
        )
        (asserts! (is-eq tx-sender (get owner license)) err-not-owner)
        (asserts! (get is-transferable license) err-unauthorized)
        (asserts! (is-license-valid license-id) err-license-expired)
        (try! (nft-transfer? digital-license license-id tx-sender recipient))
        (map-set licenses license-id (merge license {owner: recipient}))
        (ok true)
    )
)

(define-read-only (is-license-valid (license-id uint))
    (match (map-get? licenses license-id)
        some-license (let ((expiry (get expires-at some-license)))
            (if (is-some expiry)
                (> (unwrap-panic expiry) stacks-block-height)
                true))
        false)
)

(define-read-only (get-license-expiry (license-id uint))
    (let
        (
            (license (unwrap! (map-get? licenses license-id) err-invalid-license))
        )
        (ok (get expires-at license))
    )
)

(define-public (enable-dynamic-pricing (license-id uint) (strategy (string-ascii 10)) (price-multiplier uint))
    (let
        (
            (license (unwrap! (map-get? licenses license-id) err-invalid-license))
            (pricing-id (var-get next-pricing-id))
        )
        (asserts! (is-eq tx-sender (get creator license)) err-not-owner)
        (asserts! (or (is-eq strategy "surge") (or (is-eq strategy "decay") (is-eq strategy "seasonal"))) err-invalid-pricing-strategy)
        (map-set dynamic-pricing pricing-id {
            license-id: license-id,
            strategy: strategy,
            base-price: (get price license),
            current-price: (get price license),
            demand-factor: u1,
            price-multiplier: price-multiplier,
            last-updated: stacks-block-height,
            is-active: true
        })
        (var-set next-pricing-id (+ pricing-id u1))
        (ok pricing-id)
    )
)

(define-public (update-pricing (pricing-id uint))
    (let
        (
            (pricing (unwrap! (map-get? dynamic-pricing pricing-id) err-pricing-not-active))
            (license-id (get license-id pricing))
            (purchase-count (default-to u0 (map-get? license-purchase-count license-id)))
            (blocks-since-update (- stacks-block-height (get last-updated pricing)))
        )
        (asserts! (get is-active pricing) err-pricing-not-active)
        (let
            (
                (new-price (calculate-new-price pricing purchase-count blocks-since-update))
                (current-history (default-to (list) (map-get? pricing-history license-id)))
                (new-history-entry {price: new-price, timestamp: stacks-block-height})
                (updated-history (unwrap-panic (as-max-len? (append current-history new-history-entry) u20)))
            )
            (map-set dynamic-pricing pricing-id (merge pricing {
                current-price: new-price,
                demand-factor: (+ u1 (/ purchase-count u10)),
                last-updated: stacks-block-height
            }))
            (map-set pricing-history license-id updated-history)
            (ok new-price)
        )
    )
)

(define-public (disable-dynamic-pricing (pricing-id uint))
    (let
        (
            (pricing (unwrap! (map-get? dynamic-pricing pricing-id) err-pricing-not-active))
            (license (unwrap! (map-get? licenses (get license-id pricing)) err-invalid-license))
        )
        (asserts! (is-eq tx-sender (get creator license)) err-not-owner)
        (map-set dynamic-pricing pricing-id (merge pricing {is-active: false}))
        (ok true)
    )
)



(define-public (create-license (ipfs-hash (string-ascii 64)) (price uint) (usage-type (string-ascii 20)) (transferable bool))
    (let
        (
            (license-id (var-get next-license-id))
        )
        (try! (nft-mint? digital-license license-id tx-sender))
        (map-set licenses license-id {
            creator: tx-sender,
            owner: tx-sender,
            ipfs-hash: ipfs-hash,
            price: price,
            created-at: stacks-block-height,
            usage-type: usage-type,
            is-transferable: transferable,
            expires-at: none,
            is-renewable: false,
            is-collaborative: false
        })
        (var-set next-license-id (+ license-id u1))
        (var-set total-licenses (+ (var-get total-licenses) u1))
        (ok license-id)
    )
)

(define-public (create-collaborative-license (ipfs-hash (string-ascii 64)) (price uint) (usage-type (string-ascii 20)) (transferable bool) (collaborators (list 5 {collaborator: principal, share-percentage: uint})))
    (let
        (
            (license-id (var-get next-license-id))
            (total-shares (fold + (map get-share-percentage collaborators) u0))
        )
        (asserts! (is-eq total-shares u100) err-invalid-shares)
        (asserts! (> (len collaborators) u0) err-invalid-collaborator)
        (try! (nft-mint? digital-license license-id tx-sender))
        (map-set licenses license-id {
            creator: tx-sender,
            owner: tx-sender,
            ipfs-hash: ipfs-hash,
            price: price,
            created-at: stacks-block-height,
            usage-type: usage-type,
            is-transferable: transferable,
            expires-at: none,
            is-renewable: false,
            is-collaborative: true
        })
        (map-set license-collaborators license-id collaborators)
        (var-set next-license-id (+ license-id u1))
        (var-set total-licenses (+ (var-get total-licenses) u1))
        (ok license-id)
    )
)

(define-public (purchase-license (license-id uint))
    (let
        (
            (license (unwrap! (map-get? licenses license-id) err-invalid-license))
            (current-price (unwrap-panic (get-current-price license-id)))
            (creator (get creator license))
            (royalty (/ (* current-price royalty-percentage) u100))
            (is-collaborative (get is-collaborative license))
            (current-count (default-to u0 (map-get? license-purchase-count license-id)))
        )
        (try! (nft-transfer? digital-license license-id (get owner license) tx-sender))
        (if is-collaborative
            (try! (distribute-collaborative-payment license-id current-price royalty))
            (begin
                (try! (stx-transfer? current-price tx-sender (get owner license)))
                (try! (stx-transfer? royalty tx-sender creator))
                (map-set creator-royalties creator 
                    (+ (default-to u0 (map-get? creator-royalties creator)) royalty))
            )
        )
        (map-set licenses license-id (merge license {owner: tx-sender}))
        (map-set license-purchase-count license-id (+ current-count u1))
        (ok true)
    )
)

(define-private (distribute-collaborative-payment (license-id uint) (total-price uint) (total-royalty uint))
    (let
        (
            (collaborators (default-to (list) (map-get? license-collaborators license-id)))
            (license (unwrap! (map-get? licenses license-id) err-invalid-license))
            (owner (get owner license))
            (result (fold distribute-payment-to-collaborator collaborators {license-id: license-id, total-price: total-price, total-royalty: total-royalty, owner: owner, success: true}))
        )
        (if (get success result)
            (ok true)
            (err u999))
    )
)

(define-private (distribute-payment-to-collaborator (collaborator-info {collaborator: principal, share-percentage: uint}) (context {license-id: uint, total-price: uint, total-royalty: uint, owner: principal, success: bool}))
    (let
        (
            (collaborator (get collaborator collaborator-info))
            (share (get share-percentage collaborator-info))
            (payment-amount (/ (* (get total-price context) share) u100))
            (royalty-amount (/ (* (get total-royalty context) share) u100))
            (license-id (get license-id context))
        )
        (if (get success context)
            (match (stx-transfer? payment-amount tx-sender collaborator)
                success-transfer (begin
                    (match (stx-transfer? royalty-amount tx-sender collaborator)
                        success-royalty (begin
                            (map-set collaborator-earnings {license-id: license-id, collaborator: collaborator}
                                (+ (default-to u0 (map-get? collaborator-earnings {license-id: license-id, collaborator: collaborator})) (+ payment-amount royalty-amount)))
                            (map-set creator-royalties collaborator 
                                (+ (default-to u0 (map-get? creator-royalties collaborator)) royalty-amount))
                            context
                        )
                        error-royalty (merge context {success: false})
                    )
                )
                error-transfer (merge context {success: false})
            )
            context
        )
    )
)

(define-private (get-share-percentage (collaborator-info {collaborator: principal, share-percentage: uint}))
    (get share-percentage collaborator-info)
)

(define-private (min-uint (a uint) (b uint))
    (if (< a b) a b)
)

(define-private (max-uint (a uint) (b uint))
    (if (> a b) a b)
)

(define-private (calculate-new-price (pricing {license-id: uint, strategy: (string-ascii 10), base-price: uint, current-price: uint, demand-factor: uint, price-multiplier: uint, last-updated: uint, is-active: bool}) (purchase-count uint) (blocks-elapsed uint))
    (let
        (
            (base-price (get base-price pricing))
            (strategy (get strategy pricing))
            (multiplier (get price-multiplier pricing))
        )
        (if (is-eq strategy "surge")
            (min-uint (+ base-price (/ (* purchase-count multiplier) u100)) (* base-price u3))
            (if (is-eq strategy "decay")
                (max-uint (- base-price (/ (* blocks-elapsed multiplier) u1000)) (/ base-price u2))
                (if (is-eq strategy "seasonal")
                    (+ base-price (/ (* (mod stacks-block-height u10000) multiplier) u10000))
                    base-price
                )
            )
        )
    )
)

(define-read-only (get-license-collaborators (license-id uint))
    (ok (default-to (list) (map-get? license-collaborators license-id)))
)

(define-read-only (get-collaborator-earnings (license-id uint) (collaborator principal))
    (ok (default-to u0 (map-get? collaborator-earnings {license-id: license-id, collaborator: collaborator})))
)

(define-public (create-escrow (license-id uint) (seller principal) (expiry-blocks uint))
    (let
        (
            (escrow-id (var-get next-escrow-id))
            (license (unwrap! (map-get? licenses license-id) err-invalid-license))
            (price (get price license))
        )
        (asserts! (is-license-valid license-id) err-license-expired)
        (asserts! (>= (stx-get-balance tx-sender) price) err-insufficient-funds)
        (try! (stx-transfer? price tx-sender (as-contract tx-sender)))
        (map-set license-escrows escrow-id {
            buyer: tx-sender,
            seller: seller,
            license-id: license-id,
            amount: price,
            expiry-height: (+ stacks-block-height expiry-blocks),
            released: false
        })
        (var-set next-escrow-id (+ escrow-id u1))
        (ok escrow-id)
    )
)

(define-public (release-escrow (escrow-id uint))
    (let
        (
            (escrow (unwrap! (map-get? license-escrows escrow-id) err-escrow-not-found))
            (buyer (get buyer escrow))
            (seller (get seller escrow))
            (license-id (get license-id escrow))
            (amount (get amount escrow))
        )
        (asserts! (not (get released escrow)) err-escrow-already-released)
        (asserts! (or (is-eq tx-sender buyer) (is-eq tx-sender seller)) err-unauthorized)
        (asserts! (<= stacks-block-height (get expiry-height escrow)) err-escrow-expired)
        (try! (as-contract (stx-transfer? amount tx-sender seller)))
        (try! (nft-transfer? digital-license license-id seller buyer))
        (let
            (
                (license (unwrap! (map-get? licenses license-id) err-invalid-license))
            )
            (map-set licenses license-id (merge license {owner: buyer}))
        )
        (map-set license-escrows escrow-id (merge escrow {released: true}))
        (ok true)
    )
)

(define-public (refund-escrow (escrow-id uint))
    (let
        (
            (escrow (unwrap! (map-get? license-escrows escrow-id) err-escrow-not-found))
            (buyer (get buyer escrow))
            (amount (get amount escrow))
        )
        (asserts! (not (get released escrow)) err-escrow-already-released)
        (asserts! (or (is-eq tx-sender buyer) (> stacks-block-height (get expiry-height escrow))) err-unauthorized)
        (try! (as-contract (stx-transfer? amount tx-sender buyer)))
        (map-set license-escrows escrow-id (merge escrow {released: true}))
        (ok true)
    )
)

(define-read-only (get-escrow-details (escrow-id uint))
    (ok (unwrap! (map-get? license-escrows escrow-id) err-escrow-not-found))
)

(define-read-only (is-escrow-expired (escrow-id uint))
    (let
        (
            (escrow (unwrap! (map-get? license-escrows escrow-id) err-escrow-not-found))
        )
        (ok (> stacks-block-height (get expiry-height escrow)))
    )
)