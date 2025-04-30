;; campaign-reporting.clar
;; This contract provides standardized campaign finance reporting functionality to help
;; political campaigns comply with regulatory requirements. It enables candidates to generate
;; periodic reports (quarterly, annual) summarizing donation activity, categorizing donors
;; by contribution size, and identifying top contributors. The system automates compliance
;; reporting tasks that would otherwise require significant manual effort.

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-UNKNOWN-CANDIDATE (err u101))
(define-constant ERR-INVALID-PERIOD (err u102))
(define-constant ERR-INVALID-YEAR (err u103))
(define-constant ERR-REPORT-EXISTS (err u104))
(define-constant ERR-REPORT-NOT-FOUND (err u105))
(define-constant ERR-INVALID-THRESHOLD (err u106))
(define-constant ERR-NO-DONATIONS (err u107))

;; Data maps and variables

;; Tracks registered candidates who can create reports
(define-map candidates 
  { candidate-address: principal }
  { name: (string-utf8 100), active: bool })

;; Stores donation data for each candidate
(define-map candidate-donations
  { candidate-address: principal, donor-address: principal }
  { total-amount: uint, donation-count: uint, last-donation-date: uint })

;; Records all donations for reporting purposes
(define-map donation-records
  { candidate-address: principal, donation-id: uint }
  { donor-address: principal, amount: uint, date: uint, reported: bool })

;; Tracks the next donation ID for each candidate
(define-map donation-counters
  { candidate-address: principal }
  { next-id: uint })

;; Stores generated reports
(define-map financial-reports
  { candidate-address: principal, year: uint, period: (string-utf8 20) }
  { 
    total-donations: uint, 
    donor-count: uint, 
    start-date: uint, 
    end-date: uint, 
    report-date: uint, 
    finalized: bool 
  })

;; Stores detailed report statistics by donor category
(define-map report-stats
  { report-id: (tuple (candidate-address principal) (year uint) (period (string-utf8 20))), category: (string-utf8 20) }
  { donor-count: uint, total-amount: uint })

;; Stores top donors for a report
(define-map top-donors
  { report-id: (tuple (candidate-address principal) (year uint) (period (string-utf8 20))), rank: uint }
  { donor-address: principal, total-amount: uint })

;; Private functions

;; Validate report period (quarterly or annual)
(define-private (is-valid-period (period (string-utf8 20)))
  (or 
    (is-eq period "Q1")
    (is-eq period "Q2")
    (is-eq period "Q3")
    (is-eq period "Q4")
    (is-eq period "annual")))

;; Get period date range (start and end timestamps)
(define-private (get-period-range (year uint) (period (string-utf8 20)))
  (let 
    (
      (start-date 
        (if (is-eq period "annual") 
          (* year u31536000) ;; Start at beginning of year
          (+ (* year u31536000) (* 
            (if (is-eq period "Q1") u0
              (if (is-eq period "Q2") u7776000
                (if (is-eq period "Q3") u15552000
                  u23328000))) ;; Q4
            u1))))
      (end-date 
        (if (is-eq period "annual") 
          (+ (* year u31536000) u31535999) ;; End at end of year
          (+ (* year u31536000) (* 
            (if (is-eq period "Q1") u7775999
              (if (is-eq period "Q2") u15551999
                (if (is-eq period "Q3") u23327999
                  u31535999))) ;; Q4
            u1))))
    )
    {start: start-date, end: end-date}))

;; Verify if the caller is an authorized candidate
(define-private (is-authorized-candidate (candidate-address principal))
  (match (map-get? candidates {candidate-address: candidate-address})
    candidate (and (get active candidate) (is-eq tx-sender candidate-address))
    false))

;; Get the next donation ID for a candidate
(define-private (get-next-donation-id (candidate-address principal))
  (default-to 
    { next-id: u0 }
    (map-get? donation-counters {candidate-address: candidate-address})))

;; Increment the donation ID counter for a candidate
(define-private (increment-donation-counter (candidate-address principal))
  (let ((counter (get-next-donation-id candidate-address)))
    (map-set donation-counters 
      {candidate-address: candidate-address}
      {next-id: (+ (get next-id counter) u1)})))

;; Categorize donation amount into small, medium, or large
(define-private (categorize-donation (amount uint))
  (cond
    ((< amount u100) "small")
    ((< amount u1000) "medium")
    (true "large")))

;; Read-only functions

;; Get basic candidate information
(define-read-only (get-candidate-info (candidate-address principal))
  (match (map-get? candidates {candidate-address: candidate-address})
    candidate (ok candidate)
    (err ERR-UNKNOWN-CANDIDATE)))

;; Get a summary of all donations for a candidate
(define-read-only (get-donation-summary (candidate-address principal))
  (let ((counter (get-next-donation-id candidate-address)))
    (if (> (get next-id counter) u0)
      (ok {
        total-donations: (get next-id counter),
        candidate-address: candidate-address
      })
      (err ERR-NO-DONATIONS))))

;; Get a specific report
(define-read-only (get-report (candidate-address principal) (year uint) (period (string-utf8 20)))
  (match (map-get? financial-reports {candidate-address: candidate-address, year: year, period: period})
    report (ok report)
    (err ERR-REPORT-NOT-FOUND)))

;; Get report statistics for a specific category
(define-read-only (get-report-category-stats (candidate-address principal) (year uint) (period (string-utf8 20)) (category (string-utf8 20)))
  (match (map-get? report-stats 
    {
      report-id: {candidate-address: candidate-address, year: year, period: period}, 
      category: category
    })
    stats (ok stats)
    (err ERR-REPORT-NOT-FOUND)))

;; Get a top donor by rank for a specific report
(define-read-only (get-top-donor (candidate-address principal) (year uint) (period (string-utf8 20)) (rank uint))
  (match (map-get? top-donors 
    {
      report-id: {candidate-address: candidate-address, year: year, period: period}, 
      rank: rank
    })
    donor (ok donor)
    (err ERR-REPORT-NOT-FOUND)))

;; Check if a report exists
(define-read-only (report-exists (candidate-address principal) (year uint) (period (string-utf8 20)))
  (is-some (map-get? financial-reports {candidate-address: candidate-address, year: year, period: period})))

;; Public functions

;; Register a new candidate
(define-public (register-candidate (name (string-utf8 100)))
  (let ((candidate-address tx-sender))
    (if (is-some (map-get? candidates {candidate-address: candidate-address}))
      (err ERR-NOT-AUTHORIZED)
      (begin
        (map-set candidates
          {candidate-address: candidate-address}
          {name: name, active: true})
        (map-set donation-counters
          {candidate-address: candidate-address}
          {next-id: u0})
        (ok true)))))

;; Record a new donation (typically called by another contract)
(define-public (record-donation (candidate-address principal) (donor-address principal) (amount uint) (date uint))
  (if (is-authorized-candidate candidate-address)
    (let ((donation-id (get next-id (get-next-donation-id candidate-address))))
      (begin
        ;; Store the donation record
        (map-set donation-records
          {candidate-address: candidate-address, donation-id: donation-id}
          {donor-address: donor-address, amount: amount, date: date, reported: false})
        
        ;; Update donor totals
        (match (map-get? candidate-donations {candidate-address: candidate-address, donor-address: donor-address})
          existing-data
            (map-set candidate-donations
              {candidate-address: candidate-address, donor-address: donor-address}
              {
                total-amount: (+ (get total-amount existing-data) amount),
                donation-count: (+ (get donation-count existing-data) u1),
                last-donation-date: date
              })
          ;; No existing data, create new entry
          (map-set candidate-donations
            {candidate-address: candidate-address, donor-address: donor-address}
            {
              total-amount: amount,
              donation-count: u1,
              last-donation-date: date
            }))
        
        ;; Increment the donation counter
        (increment-donation-counter candidate-address)
        (ok donation-id)))
    (err ERR-NOT-AUTHORIZED)))

;; Initialize a new financial report
(define-public (init-financial-report (year uint) (period (string-utf8 20)))
  (let 
    ((candidate-address tx-sender))
    (if (not (is-authorized-candidate candidate-address))
      (err ERR-NOT-AUTHORIZED)
      (if (not (is-valid-period period))
        (err ERR-INVALID-PERIOD)
        (if (< year u2000) ;; Basic validation for year
          (err ERR-INVALID-YEAR)
          (if (report-exists candidate-address year period)
            (err ERR-REPORT-EXISTS)
            (let ((date-range (get-period-range year period)))
              (begin
                ;; Create the basic report entry
                (map-set financial-reports
                  {candidate-address: candidate-address, year: year, period: period}
                  {
                    total-donations: u0,
                    donor-count: u0,
                    start-date: (get start date-range),
                    end-date: (get end date-range),
                    report-date: block-height,
                    finalized: false
                  })
                
                ;; Initialize statistics for different donor categories
                (map-set report-stats
                  {report-id: {candidate-address: candidate-address, year: year, period: period}, category: "small"}
                  {donor-count: u0, total-amount: u0})
                
                (map-set report-stats
                  {report-id: {candidate-address: candidate-address, year: year, period: period}, category: "medium"}
                  {donor-count: u0, total-amount: u0})
                
                (map-set report-stats
                  {report-id: {candidate-address: candidate-address, year: year, period: period}, category: "large"}
                  {donor-count: u0, total-amount: u0})
                
                (ok true)))))))))

;; Generate the financial report based on recorded donations
(define-public (generate-financial-report (year uint) (period (string-utf8 20)))
  (let 
    ((candidate-address tx-sender))
    (if (not (is-authorized-candidate candidate-address))
      (err ERR-NOT-AUTHORIZED)
      (if (not (report-exists candidate-address year period))
        (err ERR-REPORT-NOT-FOUND)
        ;; In a real implementation, we would iterate through all donations in the period
        ;; Since Clarity doesn't have loops, we would either:
        ;; 1. Use a separate off-chain indexer to calculate stats
        ;; 2. Process donations incrementally as they come in
        ;; 3. Implement a batch processing approach with multiple transactions
        
        ;; For this example, we'll simulate a successful report generation
        (begin
          (map-set financial-reports
            {candidate-address: candidate-address, year: year, period: period}
            {
              total-donations: u15000, ;; Example values
              donor-count: u120,
              start-date: (get start (get-period-range year period)),
              end-date: (get end (get-period-range year period)),
              report-date: block-height,
              finalized: true
            })
          
          ;; Update category stats
          (map-set report-stats
            {report-id: {candidate-address: candidate-address, year: year, period: period}, category: "small"}
            {donor-count: u80, total-amount: u2000})
          
          (map-set report-stats
            {report-id: {candidate-address: candidate-address, year: year, period: period}, category: "medium"}
            {donor-count: u30, total-amount: u8000})
          
          (map-set report-stats
            {report-id: {candidate-address: candidate-address, year: year, period: period}, category: "large"}
            {donor-count: u10, total-amount: u5000})
          
          ;; Record top donors (in a real implementation, this would be calculated)
          (map-set top-donors
            {report-id: {candidate-address: candidate-address, year: year, period: period}, rank: u1}
            {donor-address: 'ST1SJ3DTE5DN7X54YDH5D64R3BCB6A2AG2ZQ8YPD5, total-amount: u1000})
          
          (map-set top-donors
            {report-id: {candidate-address: candidate-address, year: year, period: period}, rank: u2}
            {donor-address: 'ST2CY5V39NHDPWSXMW9QDT3HC3GD6Q6XX4CFRK9AG, total-amount: u900})
          
          (map-set top-donors
            {report-id: {candidate-address: candidate-address, year: year, period: period}, rank: u3}
            {donor-address: 'ST2JHG361ZXG51QTKY2NQCVBPPRRE2KZB1HR05NNC, total-amount: u800})
          
          (ok true))))))

;; Get donors above a certain threshold for a report
(define-public (get-donors-above-threshold (year uint) (period (string-utf8 20)) (threshold uint))
  (let
    ((candidate-address tx-sender))
    (if (not (is-authorized-candidate candidate-address))
      (err ERR-NOT-AUTHORIZED)
      (if (not (report-exists candidate-address year period))
        (err ERR-REPORT-NOT-FOUND)
        (if (< threshold u1)
          (err ERR-INVALID-THRESHOLD)
          ;; In a real implementation, we would filter donors based on the threshold
          ;; Since Clarity doesn't have this capability directly, this would typically
          ;; be implemented via an indexer or off-chain service
          
          ;; For this example, we'll return a simulated result
          (ok {
            threshold: threshold,
            donor-count: u15,
            total-amount: u12000
          }))))))

;; Finalize a report (mark it as officially submitted)
(define-public (finalize-report (year uint) (period (string-utf8 20)))
  (let
    ((candidate-address tx-sender))
    (if (not (is-authorized-candidate candidate-address))
      (err ERR-NOT-AUTHORIZED)
      (match (map-get? financial-reports 
              {candidate-address: candidate-address, year: year, period: period})
        report-data 
          (begin
            (map-set financial-reports
              {candidate-address: candidate-address, year: year, period: period}
              (merge report-data {finalized: true}))
            (ok true))
        (err ERR-REPORT-NOT-FOUND)))))