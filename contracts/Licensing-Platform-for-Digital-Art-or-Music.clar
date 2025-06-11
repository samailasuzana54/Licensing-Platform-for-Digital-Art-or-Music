(define-non-fungible-token digital-license uint)

(define-constant contract-owner tx-sender)
(define-constant royalty-percentage u5)
(define-constant err-not-owner (err u100))
(define-constant err-already-exists (err u101))
(define-constant err-invalid-license (err u102))
(define-constant err-unauthorized (err u103))

(define-data-var next-license-id uint u1)
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
        is-transferable: bool
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
            is-transferable: transferable
        })
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
        )
        (try! (stx-transfer? price tx-sender (get owner license)))
        (try! (stx-transfer? royalty tx-sender creator))
        (try! (nft-transfer? digital-license license-id (get owner license) tx-sender))
        (map-set licenses license-id (merge license {owner: tx-sender}))
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
        (try! (nft-transfer? digital-license license-id tx-sender recipient))
        (map-set licenses license-id (merge license {owner: recipient}))
        (ok true)
    )
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
