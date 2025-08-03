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

(define-data-var next-license-id uint u1)
(define-data-var next-escrow-id uint u1)
(define-data-var total-licenses uint u0)

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

(define-read-only (get-license-details (license-id uint))
    (ok (unwrap! (map-get? licenses license-id) err-invalid-license))
)

(define-read-only (get-creator-royalties (creator principal))
    (ok (default-to u0 (map-get? creator-royalties creator)))
)

(define-read-only (get-total-licenses)
    (ok (var-get total-licenses))
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
            (price (get price license))
            (creator (get creator license))
            (royalty (/ (* price royalty-percentage) u100))
            (is-collaborative (get is-collaborative license))
        )
        (try! (nft-transfer? digital-license license-id (get owner license) tx-sender))
        (if is-collaborative
            (try! (distribute-collaborative-payment license-id price royalty))
            (begin
                (try! (stx-transfer? price tx-sender (get owner license)))
                (try! (stx-transfer? royalty tx-sender creator))
                (map-set creator-royalties creator 
                    (+ (default-to u0 (map-get? creator-royalties creator)) royalty))
            )
        )
        (map-set licenses license-id (merge license {owner: tx-sender}))
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