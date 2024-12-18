;; Pension Fund Smart Contract

;; Define constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERROR_UNAUTHORIZED (err u100))
(define-constant ERROR_INVALID_AMOUNT (err u101))
(define-constant ERROR_INSUFFICIENT_BALANCE (err u102))
(define-constant ERROR_NOT_ELIGIBLE (err u103))
(define-constant ERROR_INVALID_INVESTMENT_OPTION (err u104))
(define-constant ERROR_NOT_REGISTERED_EMPLOYER (err u105))
(define-constant ERROR_INVALID_INPUT_PARAMETER (err u106))
(define-constant ERROR_EMPLOYER_ALREADY_REGISTERED (err u107))
(define-constant REQUIRED_VESTING_YEARS u5) ;; 5 years vesting period
(define-constant EARLY_WITHDRAWAL_PENALTY_BASIS_POINTS u10) ;; 10% penalty
(define-constant MAXIMUM_ALLOWED_RETIREMENT_AGE u100)
(define-constant MINIMUM_ALLOWED_BIRTH_YEAR u1900)
(define-constant MAXIMUM_ALLOWED_BIRTH_YEAR u2100)

;; Define variables
(define-data-var DEFAULT_RETIREMENT_AGE uint u65)
(define-data-var INVESTMENT_OPTION_COUNTER uint u1)

;; Define data maps
(define-map PARTICIPANT_INVESTMENT_BALANCES 
  { PARTICIPANT_ADDRESS: principal, INVESTMENT_OPTION_ID: uint } 
  { TOTAL_INVESTED_AMOUNT: uint, VESTED_INVESTMENT_AMOUNT: uint }
)
(define-map PARTICIPANT_DETAILS 
  principal 
  { ENROLLMENT_BLOCK: uint, 
    PARTICIPANT_BIRTH_YEAR: uint,
    CURRENT_EMPLOYER_ADDRESS: (optional principal) }
)
(define-map AUTHORIZED_EMPLOYERS principal bool)
(define-map AVAILABLE_INVESTMENT_OPTIONS uint { INVESTMENT_NAME: (string-ascii 20), INVESTMENT_RISK_LEVEL: uint })

;; Private functions

(define-private (calculate-total-vested-amount (participant-address principal) (investment-option-id uint))
  (match (map-get? PARTICIPANT_DETAILS participant-address)
    participant-profile 
      (let (
        (investment-balance (default-to { TOTAL_INVESTED_AMOUNT: u0, VESTED_INVESTMENT_AMOUNT: u0 } 
                  (map-get? PARTICIPANT_INVESTMENT_BALANCES 
                    { PARTICIPANT_ADDRESS: participant-address, INVESTMENT_OPTION_ID: investment-option-id })))
        (participation-years (/ (- block-height (get ENROLLMENT_BLOCK participant-profile)) u52560))
      )
        (if (>= participation-years REQUIRED_VESTING_YEARS)
          (get TOTAL_INVESTED_AMOUNT investment-balance)
          (get VESTED_INVESTMENT_AMOUNT investment-balance)
        )
      )
    u0  ;; Return 0 if the participant profile doesn't exist
  )
)

(define-private (validate-birth-year (birth-year uint))
  (and (>= birth-year MINIMUM_ALLOWED_BIRTH_YEAR) (<= birth-year MAXIMUM_ALLOWED_BIRTH_YEAR))
)

(define-private (validate-investment-option (investment-option-id uint))
  (is-some (map-get? AVAILABLE_INVESTMENT_OPTIONS investment-option-id))
)

;; Public functions

;; Function to enroll in the pension fund
(define-public (enroll-participant (birth-year uint))
  (let ((participant-address tx-sender))
    (asserts! (is-none (map-get? PARTICIPANT_DETAILS participant-address)) ERROR_UNAUTHORIZED)
    (asserts! (validate-birth-year birth-year) ERROR_INVALID_INPUT_PARAMETER)
    (ok (map-set PARTICIPANT_DETAILS 
      participant-address 
      { ENROLLMENT_BLOCK: block-height, PARTICIPANT_BIRTH_YEAR: birth-year, CURRENT_EMPLOYER_ADDRESS: none }
    ))
  )
)

;; Function for participant contribution
(define-public (make-participant-contribution (contribution-amount uint) (investment-option-id uint))
  (let (
    (participant-address tx-sender)
    (current-investment-balance (default-to { TOTAL_INVESTED_AMOUNT: u0, VESTED_INVESTMENT_AMOUNT: u0 } 
      (map-get? PARTICIPANT_INVESTMENT_BALANCES { PARTICIPANT_ADDRESS: participant-address, INVESTMENT_OPTION_ID: investment-option-id })))
  )
    (asserts! (> contribution-amount u0) ERROR_INVALID_AMOUNT)
    (asserts! (is-some (map-get? PARTICIPANT_DETAILS participant-address)) ERROR_UNAUTHORIZED)
    (asserts! (validate-investment-option investment-option-id) ERROR_INVALID_INVESTMENT_OPTION)
    (try! (stx-transfer? contribution-amount participant-address (as-contract tx-sender)))
    (ok (map-set PARTICIPANT_INVESTMENT_BALANCES 
      { PARTICIPANT_ADDRESS: participant-address, INVESTMENT_OPTION_ID: investment-option-id }
      { TOTAL_INVESTED_AMOUNT: (+ (get TOTAL_INVESTED_AMOUNT current-investment-balance) contribution-amount),
        VESTED_INVESTMENT_AMOUNT: (+ (get VESTED_INVESTMENT_AMOUNT current-investment-balance) contribution-amount) }
    ))
  )
)

;; Function for employer contribution
(define-public (make-employer-contribution (contribution-amount uint) (investment-option-id uint) (employee-address principal))
  (let (
    (employer-address tx-sender)
    (current-investment-balance (default-to { TOTAL_INVESTED_AMOUNT: u0, VESTED_INVESTMENT_AMOUNT: u0 } 
      (map-get? PARTICIPANT_INVESTMENT_BALANCES { PARTICIPANT_ADDRESS: employee-address, INVESTMENT_OPTION_ID: investment-option-id })))
  )
    (asserts! (is-authorized-employer employer-address) ERROR_NOT_REGISTERED_EMPLOYER)
    (asserts! (> contribution-amount u0) ERROR_INVALID_AMOUNT)
    (asserts! (validate-investment-option investment-option-id) ERROR_INVALID_INVESTMENT_OPTION)
    (asserts! (is-some (map-get? PARTICIPANT_DETAILS employee-address)) ERROR_UNAUTHORIZED)
    (try! (stx-transfer? contribution-amount employer-address (as-contract tx-sender)))
    (ok (map-set PARTICIPANT_INVESTMENT_BALANCES 
      { PARTICIPANT_ADDRESS: employee-address, INVESTMENT_OPTION_ID: investment-option-id }
      { TOTAL_INVESTED_AMOUNT: (+ (get TOTAL_INVESTED_AMOUNT current-investment-balance) contribution-amount),
        VESTED_INVESTMENT_AMOUNT: (get VESTED_INVESTMENT_AMOUNT current-investment-balance) }
    ))
  )
)

;; Function to process withdrawals
(define-public (process-participant-withdrawal (withdrawal-amount uint) (investment-option-id uint))
  (let (
    (participant-address tx-sender)
    (current-investment-balance (default-to { TOTAL_INVESTED_AMOUNT: u0, VESTED_INVESTMENT_AMOUNT: u0 } 
      (map-get? PARTICIPANT_INVESTMENT_BALANCES { PARTICIPANT_ADDRESS: participant-address, INVESTMENT_OPTION_ID: investment-option-id })))
    (vested-amount (calculate-total-vested-amount participant-address investment-option-id))
  )
    (asserts! (is-some (map-get? PARTICIPANT_DETAILS participant-address)) ERROR_UNAUTHORIZED)
    (asserts! (validate-investment-option investment-option-id) ERROR_INVALID_INVESTMENT_OPTION)
    (asserts! (<= withdrawal-amount (get TOTAL_INVESTED_AMOUNT current-investment-balance)) ERROR_INSUFFICIENT_BALANCE)
    (if (check-retirement-eligibility participant-address)
      (begin
        (try! (as-contract (stx-transfer? withdrawal-amount (as-contract tx-sender) participant-address)))
        (ok (map-set PARTICIPANT_INVESTMENT_BALANCES 
          { PARTICIPANT_ADDRESS: participant-address, INVESTMENT_OPTION_ID: investment-option-id }
          { TOTAL_INVESTED_AMOUNT: (- (get TOTAL_INVESTED_AMOUNT current-investment-balance) withdrawal-amount),
            VESTED_INVESTMENT_AMOUNT: (- vested-amount withdrawal-amount) }
        ))
      )
      (if (<= withdrawal-amount vested-amount)
        (let (
          (early-withdrawal-penalty (/ (* withdrawal-amount EARLY_WITHDRAWAL_PENALTY_BASIS_POINTS) u100))
          (net-withdrawal-amount (- withdrawal-amount early-withdrawal-penalty))
        )
          (try! (as-contract (stx-transfer? net-withdrawal-amount (as-contract tx-sender) participant-address)))
          (ok (map-set PARTICIPANT_INVESTMENT_BALANCES 
            { PARTICIPANT_ADDRESS: participant-address, INVESTMENT_OPTION_ID: investment-option-id }
            { TOTAL_INVESTED_AMOUNT: (- (get TOTAL_INVESTED_AMOUNT current-investment-balance) withdrawal-amount),
              VESTED_INVESTMENT_AMOUNT: (- vested-amount withdrawal-amount) }
          ))
        )
        ERROR_NOT_ELIGIBLE
      )
    )
  )
)

;; Read-only functions

;; Get participant's investment balance
(define-read-only (get-participant-balance (participant-address principal) (investment-option-id uint))
  (default-to { TOTAL_INVESTED_AMOUNT: u0, VESTED_INVESTMENT_AMOUNT: u0 } 
    (map-get? PARTICIPANT_INVESTMENT_BALANCES { PARTICIPANT_ADDRESS: participant-address, INVESTMENT_OPTION_ID: investment-option-id }))
)

;; Get participant's profile information
(define-read-only (get-participant-profile (participant-address principal))
  (map-get? PARTICIPANT_DETAILS participant-address)
)

;; Check participant's retirement eligibility
(define-read-only (check-retirement-eligibility (participant-address principal))
  (match (get-participant-profile participant-address)
    participant-profile 
      (>= (- block-height (get ENROLLMENT_BLOCK participant-profile)) 
          (* (var-get DEFAULT_RETIREMENT_AGE) u52560))
    false
  )
)

;; Get investment option details
(define-read-only (get-investment-option-details (option-id uint))
  (map-get? AVAILABLE_INVESTMENT_OPTIONS option-id)
)

;; Check if address is authorized employer
(define-read-only (is-authorized-employer (employer-address principal))
  (default-to false (map-get? AUTHORIZED_EMPLOYERS employer-address))
)

;; Contract owner functions

;; Update retirement age
(define-public (update-default-retirement-age (new-retirement-age uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERROR_UNAUTHORIZED)
    (asserts! (<= new-retirement-age MAXIMUM_ALLOWED_RETIREMENT_AGE) ERROR_INVALID_INPUT_PARAMETER)
    (ok (var-set DEFAULT_RETIREMENT_AGE new-retirement-age))
  )
)

;; Add new investment option
(define-public (create-investment-option (investment-name (string-ascii 20)) (risk-level uint))
  (let ((option-id (var-get INVESTMENT_OPTION_COUNTER)))
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERROR_UNAUTHORIZED)
    (asserts! (<= risk-level u10) ERROR_INVALID_INPUT_PARAMETER)
    (asserts! (> (len investment-name) u0) ERROR_INVALID_INPUT_PARAMETER)
    (ok (begin
      (map-set AVAILABLE_INVESTMENT_OPTIONS option-id 
        { INVESTMENT_NAME: investment-name, INVESTMENT_RISK_LEVEL: risk-level })
      (var-set INVESTMENT_OPTION_COUNTER (+ option-id u1))
      option-id
    ))
  )
)

;; Register a new employer
(define-public (register-new-employer (employer-address principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERROR_UNAUTHORIZED)
    (asserts! (is-none (map-get? AUTHORIZED_EMPLOYERS employer-address)) ERROR_EMPLOYER_ALREADY_REGISTERED)
    (ok (map-set AUTHORIZED_EMPLOYERS employer-address true))
  )
)

;; Update employee's employer information
(define-public (update-employee-employer (employee-address principal) (employer-address principal))
  (begin
    (asserts! (is-authorized-employer tx-sender) ERROR_NOT_REGISTERED_EMPLOYER)
    (asserts! (is-authorized-employer employer-address) ERROR_NOT_REGISTERED_EMPLOYER)
    (asserts! (is-some (map-get? PARTICIPANT_DETAILS employee-address)) ERROR_UNAUTHORIZED)
    (ok (map-set PARTICIPANT_DETAILS 
      employee-address 
      (merge (unwrap-panic (map-get? PARTICIPANT_DETAILS employee-address))
             { CURRENT_EMPLOYER_ADDRESS: (some employer-address) })
    ))
  )
)