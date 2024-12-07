;; Political Donation Tracker Contract

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-not-authorized (err u100))
(define-constant err-invalid-amount (err u101))
(define-constant err-candidate-not-found (err u102))

;; Data Variables
(define-data-var minimum-donation uint u1000000) ;; 1 STX minimum

;; Data Maps
(define-map candidates principal
    {
        name: (string-ascii 50),
        party: (string-ascii 50),
        total-donations: uint,
        registered: bool
    }
)

(define-map donations
    { donor: principal, candidate: principal }
    {
        amount: uint,
        timestamp: uint,
        message: (optional (string-utf8 280))
    }
)

;; Public Functions
(define-public (register-candidate (name (string-ascii 50)) (party (string-ascii 50)))
    (if (is-eq tx-sender contract-owner)
        (begin
            (map-set candidates tx-sender {
                name: name,
                party: party,
                total-donations: u0,
                registered: true
            })
            (ok true)
        )
        err-not-authorized
    )
)

(define-public (make-donation (candidate principal) (amount uint) (message (optional (string-utf8 280))))
    (let (
        (candidate-info (unwrap! (map-get? candidates candidate) err-candidate-not-found))
        (donation-key { donor: tx-sender, candidate: candidate })
    )
        (asserts! (>= amount (var-get minimum-donation)) err-invalid-amount)
        (try! (stx-transfer? amount tx-sender candidate))
        (map-set donations donation-key {
            amount: amount,
            timestamp: block-height,
            message: message
        })
        (map-set candidates candidate 
            (merge candidate-info { 
                total-donations: (+ amount (get total-donations candidate-info))
            })
        )
        (ok true)
    )
)

;; Read Only Functions
(define-read-only (get-candidate-info (candidate principal))
    (ok (map-get? candidates candidate))
)

(define-read-only (get-donation-info (donor principal) (candidate principal))
    (ok (map-get? donations { donor: donor, candidate: candidate }))
)

(define-read-only (get-minimum-donation)
    (ok (var-get minimum-donation))
)
