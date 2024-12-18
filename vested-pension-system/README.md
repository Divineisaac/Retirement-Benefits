# Pension Fund Smart Contract

A Clarity smart contract implementing a comprehensive pension fund system with employer contributions, vesting periods, and multiple investment options.

## About

This smart contract provides a complete pension fund management system with the following key features:
- Participant enrollment and management
- Employer and employee contributions
- Investment options with different risk levels
- Vesting schedule implementation
- Retirement eligibility checking
- Early withdrawal penalties
- Employer registration and authorization

## Key Parameters

- Default retirement age: 65 years
- Vesting period: 5 years
- Early withdrawal penalty: 10% (1000 basis points)
- Maximum retirement age: 100 years
- Valid birth year range: 1900-2100

## Core Functions

### For Participants

1. `enroll-participant (birth-year uint)`
   - Enrolls a new participant in the pension fund
   - Requires valid birth year between 1900-2100
   - Can only enroll once

2. `make-participant-contribution (contribution-amount uint) (investment-option-id uint)`
   - Makes a contribution to the participant's pension fund
   - Amount must be greater than 0
   - Requires valid investment option ID

3. `process-participant-withdrawal (withdrawal-amount uint) (investment-option-id uint)`
   - Processes withdrawal requests
   - Applies early withdrawal penalty if not retirement eligible
   - Cannot withdraw more than available balance
   - Checks vesting status for non-retirement withdrawals

### For Employers

1. `make-employer-contribution (contribution-amount uint) (investment-option-id uint) (employee-address principal)`
   - Makes employer contributions to employee pension funds
   - Only authorized employers can contribute
   - Requires valid employee address and investment option

2. `update-employee-employer (employee-address principal) (employer-address principal)`
   - Updates employee's current employer information
   - Only authorized employers can update

### Administrative Functions

1. `update-default-retirement-age (new-retirement-age uint)`
   - Updates the default retirement age
   - Only contract owner can modify
   - Must be less than maximum allowed retirement age

2. `create-investment-option (investment-name (string-ascii 20)) (risk-level uint)`
   - Creates new investment options
   - Risk level must be between 0-10
   - Only contract owner can create

3. `register-new-employer (employer-address principal)`
   - Registers new authorized employers
   - Only contract owner can register
   - Cannot register same employer twice

### Read-Only Functions

1. `get-participant-balance (participant-address principal) (investment-option-id uint)`
   - Returns participant's total and vested investment amounts

2. `get-participant-profile (participant-address principal)`
   - Returns participant's enrollment details and current employer

3. `check-retirement-eligibility (participant-address principal)`
   - Checks if participant is eligible for retirement

4. `get-investment-option-details (option-id uint)`
   - Returns investment option name and risk level

5. `is-authorized-employer (employer-address principal)`
   - Checks if an address is an authorized employer

## Error Codes

- `ERROR_UNAUTHORIZED (u100)`: Unauthorized access attempt
- `ERROR_INVALID_AMOUNT (u101)`: Invalid contribution/withdrawal amount
- `ERROR_INSUFFICIENT_BALANCE (u102)`: Insufficient funds for withdrawal
- `ERROR_NOT_ELIGIBLE (u103)`: Not eligible for requested operation
- `ERROR_INVALID_INVESTMENT_OPTION (u104)`: Invalid investment option ID
- `ERROR_NOT_REGISTERED_EMPLOYER (u105)`: Employer not registered
- `ERROR_INVALID_INPUT_PARAMETER (u106)`: Invalid input parameters
- `ERROR_EMPLOYER_ALREADY_REGISTERED (u107)`: Duplicate employer registration

## Implementation Notes

- Uses block height for time-based calculations (52560 blocks per year)
- Implements vesting through separate tracking of total and vested amounts
- Supports multiple investment options with different risk levels
- Maintains separation of employer and employee contributions for vesting
- Includes safety checks for all critical operations
- Uses descriptive naming conventions for better code readability

## Security Considerations

1. All sensitive functions are protected with appropriate authorization checks
2. Mathematical operations include overflow protection
3. State changes are atomic and consistent
4. Input validation is performed for all public functions
5. Separation of concerns between participant, employer, and admin functions

## Usage Example

```clarity
;; Enroll in the pension fund
(contract-call? .pension-fund enroll-participant u1990)

;; Make a contribution
(contract-call? .pension-fund make-participant-contribution u1000 u1)

;; Check balance
(contract-call? .pension-fund get-participant-balance tx-sender u1)
```