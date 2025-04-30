;; donor-verification
;; 
;; This contract implements a donor verification system for political donations with multiple
;; verification levels to ensure donation legitimacy and enhance transparency.
;; Donors can be verified at different levels (basic, enhanced, certified) and candidates
;; can choose to accept donations only from verified donors of specific levels.

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ADMIN-ONLY (err u101))
(define-constant ERR-DONOR-NOT-FOUND (err u102))
(define-constant ERR-INVALID-VERIFICATION-LEVEL (err u103))
(define-constant ERR-ALREADY-VERIFIED (err u104))
(define-constant ERR-VERIFICATION-REQUIRED (err u105))
(define-constant ERR-INSUFFICIENT-VERIFICATION-LEVEL (err u106))
(define-constant ERR-CANDIDATE-NOT-FOUND (err u107))

;; Verification levels
(define-constant LEVEL-NONE u0)
(define-constant LEVEL-BASIC u1)
(define-constant LEVEL-ENHANCED u2)
(define-constant LEVEL-CERTIFIED u3)

;; Data space definitions

;; Contract administrator - has the authority to verify donors
(define-data-var contract-admin principal tx-sender)

;; Map to store verification status of donors
;; Principal -> Verification Level (u0 = not verified, u1 = basic, u2 = enhanced, u3 = certified)
(define-map donor-verification-status
  { donor: principal }
  { verification-level: uint,
    verification-date: uint }
)

;; Map to store candidate verification requirements
;; Principal -> Minimum verification level required for donations
(define-map candidate-requirements
  { candidate: principal }
  { min-verification-level: uint,
    min-donation-amount: uint }
)

;; Map to store verification metadata for donors
(define-map donor-verification-metadata
  { donor: principal }
  { full-name: (string-utf8 100),
    address: (string-utf8 200),
    id-document-hash: (buff 32),
    verification-notes: (string-utf8 500) }
)

;; Private functions

;; Check if the caller is the contract administrator
(define-private (is-admin)
  (is-eq tx-sender (var-get contract-admin))
)

;; Check if a verification level is valid
(define-private (is-valid-verification-level (level uint))
  (and (>= level LEVEL-NONE) (<= level LEVEL-CERTIFIED))
)

;; Check if a donor exists and has at least a specific verification level
(define-private (is-verified-at-level (donor principal) (required-level uint))
  (match (map-get? donor-verification-status { donor: donor })
    verification-info (>= (get verification-level verification-info) required-level)
    false
  )
)

;; Read-only functions

;; Get the verification status of a donor
(define-read-only (get-donor-verification-status (donor principal))
  (default-to 
    { verification-level: LEVEL-NONE, verification-date: u0 }
    (map-get? donor-verification-status { donor: donor })
  )
)

;; Get the verification requirements for a candidate
(define-read-only (get-candidate-requirements (candidate principal))
  (default-to
    { min-verification-level: LEVEL-NONE, min-donation-amount: u0 }
    (map-get? candidate-requirements { candidate: candidate })
  )
)

;; Check if a donor meets a candidate's verification requirements for a specific donation amount
(define-read-only (can-donate-to-candidate (donor principal) (candidate principal) (amount uint))
  (let ((donor-status (get-donor-verification-status donor))
        (candidate-reqs (get-candidate-requirements candidate)))
    
    ;; If donation amount is less than the minimum threshold, no verification needed
    (if (< amount (get min-donation-amount candidate-reqs))
      (ok true)
      ;; Otherwise, check if donor meets the verification level
      (if (>= (get verification-level donor-status) (get min-verification-level candidate-reqs))
        (ok true)
        (err ERR-INSUFFICIENT-VERIFICATION-LEVEL)
      )
    )
  )
)

;; Get donor verification metadata
(define-read-only (get-donor-metadata (donor principal))
  (map-get? donor-verification-metadata { donor: donor })
)

;; Public functions

;; Set or update the contract administrator
(define-public (set-contract-admin (new-admin principal))
  (begin
    (asserts! (is-admin) ERR-ADMIN-ONLY)
    (ok (var-set contract-admin new-admin))
  )
)

;; Verify a donor at a specific level (admin only)
(define-public (verify-donor 
  (donor principal) 
  (level uint) 
  (full-name (string-utf8 100))
  (address (string-utf8 200))
  (id-document-hash (buff 32))
  (verification-notes (string-utf8 500)))
  
  (begin
    ;; Check authorization and verification level validity
    (asserts! (is-admin) ERR-ADMIN-ONLY)
    (asserts! (is-valid-verification-level level) ERR-INVALID-VERIFICATION-LEVEL)
    (asserts! (> level LEVEL-NONE) ERR-INVALID-VERIFICATION-LEVEL)
    
    ;; Store verification status
    (map-set donor-verification-status
      { donor: donor }
      { verification-level: level, 
        verification-date: block-height }
    )
    
    ;; Store verification metadata
    (map-set donor-verification-metadata
      { donor: donor }
      { full-name: full-name,
        address: address,
        id-document-hash: id-document-hash,
        verification-notes: verification-notes }
    )
    
    (ok level)
  )
)

;; Revoke verification from a donor (admin only)
(define-public (revoke-verification (donor principal))
  (begin
    (asserts! (is-admin) ERR-ADMIN-ONLY)
    
    ;; Check if donor exists in the verification map
    (asserts! (is-some (map-get? donor-verification-status { donor: donor })) ERR-DONOR-NOT-FOUND)
    
    ;; Remove verification by setting level to 0
    (map-set donor-verification-status
      { donor: donor }
      { verification-level: LEVEL-NONE, 
        verification-date: block-height }
    )
    
    (ok true)
  )
)

;; Allow a candidate to set their verification requirements
(define-public (set-candidate-requirements (min-level uint) (min-amount uint))
  (begin
    (asserts! (is-valid-verification-level min-level) ERR-INVALID-VERIFICATION-LEVEL)
    
    (map-set candidate-requirements
      { candidate: tx-sender }
      { min-verification-level: min-level,
        min-donation-amount: min-amount }
    )
    
    (ok true)
  )
)

;; Self-registration for basic verification
;; This allows donors to start the verification process themselves
(define-public (register-for-verification 
  (full-name (string-utf8 100))
  (address (string-utf8 200)))
  
  (begin
    ;; Check if already verified at a higher level than basic
    (let ((current-status (get-donor-verification-status tx-sender)))
      (asserts! (<= (get verification-level current-status) LEVEL-BASIC) ERR-ALREADY-VERIFIED)
      
      ;; Set basic verification status
      (map-set donor-verification-status
        { donor: tx-sender }
        { verification-level: LEVEL-BASIC, 
          verification-date: block-height }
      )
      
      ;; Store basic metadata
      (map-set donor-verification-metadata
        { donor: tx-sender }
        { full-name: full-name,
          address: address,
          id-document-hash: 0x0000000000000000000000000000000000000000000000000000000000000000,
          verification-notes: "Self-registered for basic verification" }
      )
      
      (ok LEVEL-BASIC)
    )
  )
)

;; Helper function for other contracts to check if a donor is sufficiently verified
(define-public (check-donation-eligibility (donor principal) (amount uint) (required-level uint))
  (let ((donor-status (get-donor-verification-status donor)))
    (if (>= amount u0)
      (if (>= (get verification-level donor-status) required-level)
        (ok true)
        ERR-INSUFFICIENT-VERIFICATION-LEVEL
      )
      ERR-INVALID-VERIFICATION-LEVEL
    )
  )
)