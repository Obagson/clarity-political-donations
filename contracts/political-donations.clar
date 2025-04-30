```clarity
;; Political Donation Tracker Contract

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-not-authorized (err u100))
(define-constant err-invalid-amount (err u101))
(define-constant err-candidate-not-found (err u102))
(define-constant err-donation-cap-exceeded (err u103))
(define-constant err-donation-not-found (err u104))
(define-constant err-insufficient-balance (err u105))

;; Data Variables
(define-data-var minimum-donation uint u1000000) ;; 1 STX minimum
(define-data-var single-donation-cap uint u100000000) ;; 100 STX max per donation
(define-data-var cumulative-donation-cap uint u500000000) ;; 500 STX max per donor per candidate

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
        message: (optional (string-utf8 280)),
        refunded: bool
    }
)

(define-map donor-totals
    { donor: principal, candidate: principal }
    {
        total-donated: uint,
        daily-donations: (list 10 {day: uint, amount: uint}),
        monthly-donations: (list 10 {month: uint, amount: uint})
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
        (donor-total-info (default-to 
            { total-donated: u0, daily-donations: (list), monthly-donations: (list) } 
            (map-get? donor-totals donation-key)))
        (current-day (/ block-height u144))
        (current-month (/ block-height u4320))
    )
        (asserts! (>= amount (var-get minimum-donation)) err-invalid-amount)
        (asserts! (<= amount (var-get single-donation-cap)) err-donation-cap-exceeded)
        (asserts! (<= (+ amount (get total-donated donor-total-info)) (var-get cumulative-donation-cap)) err-donation-cap-exceeded)
        
        (try! (stx-transfer? amount tx-sender candidate))
        
        (map-set donations donation-key {
            amount: amount,
            timestamp: block-height,
            message: message,
            refunded: false
        })
        
        (map-set candidates candidate 
            (merge candidate-info { 
                total-donations: (+ amount (get total-donations candidate-info))
            })
        )
        
        (map-set donor-totals donation-key {
            total-donated: (+ amount (get total-donated donor-total-info)),
            daily-donations: (update-time-series 
                (get daily-donations donor-total-info) 
                current-day 
                amount),
            monthly-donations: (update-time-series 
                (get monthly-donations donor-total-info) 
                current-month 
                amount)
        })
        
        (ok true)
    )
)

(define-public (refund-donation (donor principal) (candidate principal))
    (let (
        (donation-key { donor: donor, candidate: candidate })
        (donation-info (unwrap! (map-get? donations donation-key) err-donation-not-found))
        (candidate-info (unwrap! (map-get? candidates candidate) err-candidate-not-found))
        (donor-total-info (unwrap! (map-get? donor-totals donation-key) err-donation-not-found))
        (refund-amount (get amount donation-info))
    )
        (asserts! (is-eq tx-sender candidate) err-not-authorized)
        (asserts! (not (get refunded donation-info)) err-donation-not-found)
        
        (try! (stx-transfer? refund-amount candidate donor))
        
        (map-set donations donation-key
            (merge donation-info { refunded: true })
        )
        
        (map-set candidates candidate
            (merge candidate-info {
                total-donations: (- (get total-donations candidate-info) refund-amount)
            })
        )
        
        (map-set donor-totals donation-key
            (merge donor-total-info {
                total-donated: (- (get total-donated donor-total-info) refund-amount)
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

(define-read-only (get-donation-caps)
    (ok {
        single-donation-cap: (var-get single-donation-cap),
        cumulative-donation-cap: (var-get cumulative-donation-cap)
    })
)

(define-read-only (get-donor-analytics (donor principal) (candidate principal))
    (ok (map-get? donor-totals { donor: donor, candidate: candidate }))
)

(define-read-only (get-daily-donation-total (donor principal) (candidate principal) (day uint))
    (let (
        (donor-data (default-to 
            { total-donated: u0, daily-donations: (list), monthly-donations: (list) }
            (map-get? donor-totals { donor: donor, candidate: candidate })))
        (day-data (get-time-series-entry (get daily-donations donor-data) day))
    )
        (ok day-data)
    )
)

(define-read-only (get-monthly-donation-total (donor principal) (candidate principal) (month uint))
    (let (
        (donor-data (default-to 
            { total-donated: u0, daily-donations: (list), monthly-donations: (list) }
            (map-get? donor-totals { donor: donor, candidate: candidate })))
        (month-data (get-time-series-entry (get monthly-donations donor-data) month))
    )
        (ok month-data)
    )
)

;; Private Functions
(define-private (update-time-series (series (list 10 {day: uint, amount: uint})) (period uint) (amount uint))
    (let (
        (existing-entry (find-entry series period))
    )
        (if (is-some existing-entry)
            (update-existing-entry series period amount)
            (add-new-entry series period amount)
        )
    )
)

(define-private (find-entry (series (list 10 {day: uint, amount: uint})) (period uint))
    (filter (lambda (entry) (is-eq (get day entry) period)) series)
)

(define-private (update-existing-entry (series (list 10 {day: uint, amount: uint})) (period uint) (amount uint))
    (map 
        (lambda (entry) 
            (if (is-eq (get day entry) period)
                {day: period, amount: (+ (get amount entry) amount)}
                entry
            )
        )
        series
    )
)

(define-private (add-new-entry (series (list 10 {day: uint, amount: uint})) (period uint) (amount uint))
    (let (
        (series-length (len series))
    )
        (if (< series-length u10)
            (append series {day: period, amount: amount})
            (unwrap-panic (as-max-len? (concat (list {day: period, amount: amount}) (slice series u0 u9)) u10))
        )
    )
)

(define-private (get-time-series-entry (series (list 10 {day: uint, amount: uint})) (period uint))
    (default-to {day: period, amount: u0}
        (element-at 
            (filter (lambda (entry) (is-eq (get day entry) period)) series)
            u0
        )
    )
)
```