;; Safe Token Launchpad
;; Uses Clarity 4 features: contract-hash?, restrict-assets?
;; Verified token launches with rug-pull protection

;; Traits
(use-trait ft-trait .sip-010-trait-v4.sip-010-trait)

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_TOKEN_NOT_VERIFIED (err u101))
(define-constant ERR_TOKEN_ALREADY_LISTED (err u102))
(define-constant ERR_INVALID_HASH (err u103))
(define-constant ERR_POOL_NOT_FOUND (err u104))
(define-constant ERR_INSUFFICIENT_LIQUIDITY (err u105))
(define-constant ERR_SLIPPAGE_TOO_HIGH (err u106))
(define-constant ERR_ZERO_AMOUNT (err u107))
(define-constant ERR_LAUNCH_NOT_ACTIVE (err u108))
(define-constant ERR_LAUNCH_ENDED (err u109))
(define-constant ERR_MIN_NOT_REACHED (err u110))
(define-constant ERR_ALREADY_CLAIMED (err u111))
(define-constant ERR_ASSET_RESTRICTION_FAILED (err u112))
(define-constant ERR_WHITELIST_REQUIRED (err u113))
(define-constant ERR_VESTING_NOT_FOUND (err u114))
(define-constant ERR_VESTING_NOT_STARTED (err u115))
(define-constant ERR_NO_TOKENS_AVAILABLE (err u116))
(define-constant ERR_INVALID_VESTING_SCHEDULE (err u117))
(define-constant ERR_LOCKUP_NOT_FOUND (err u118))
(define-constant ERR_LOCKUP_ACTIVE (err u119))
(define-constant ERR_LOCKUP_EXISTS (err u120))
(define-constant ERR_INVALID_LOCKUP_DURATION (err u121))
(define-constant ERR_INSURANCE_NOT_FOUND (err u122))
(define-constant ERR_INSURANCE_EXISTS (err u123))
(define-constant ERR_INVALID_INSURANCE (err u124))
(define-constant ERR_CLAIM_NOT_FOUND (err u125))
(define-constant ERR_CLAIM_EXISTS (err u126))
(define-constant ERR_MILESTONE_NOT_MET (err u127))

;; Fee constants (in basis points, 100 = 1%)
(define-constant LISTING_FEE u10000000) ;; 10 STX listing fee
(define-constant SWAP_FEE_BPS u30) ;; 0.3% swap fee
(define-constant PROTOCOL_FEE_BPS u10) ;; 0.1% protocol fee

;; Launch duration (24 hours in seconds)
(define-constant LAUNCH_DURATION u86400)

;; Data Variables
(define-data-var total-pools uint u0)
(define-data-var total-launches uint u0)
(define-data-var protocol-fees-collected uint u0)
(define-data-var paused bool false)
(define-data-var min-launch-amount uint u100000000)
(define-data-var max-launch-cap uint u1000000000000)
(define-data-var emergency-withdraw-enabled bool false)
(define-data-var total-volume uint u0)

;; Approved contract hashes for token templates
(define-map approved-hashes
  { hash: (buff 32) }
  { 
    name: (string-ascii 64),
    approved-at: uint,
    approved-by: principal
  }
)

;; Token listings
(define-map token-listings
  { token: principal }
  {
    pool-id: uint,
    verified: bool,
    contract-hash: (buff 32),
    listed-at: uint,
    lister: principal,
    stx-reserve: uint,
    token-reserve: uint,
    total-fees-earned: uint
  }
)

;; Launch pools (fair launch mechanism)
(define-map launch-pools
  { launch-id: uint }
  {
    token: principal,
    creator: principal,
    stx-raised: uint,
    tokens-for-sale: uint,
    min-raise: uint,
    max-raise: uint,
    start-time: uint,
    end-time: uint,
    finalized: bool,
    successful: bool
  }
)

;; Contributions to launches
(define-map launch-contributions
  { launch-id: uint, contributor: principal }
  {
    amount: uint,
    claimed: bool
  }
)

;; Whitelist for private launches
(define-map launch-whitelist
  { launch-id: uint, user: principal }
  {
    whitelisted-at: uint,
    max-contribution: uint,      ;; Individual cap for this user
    contributed-amount: uint      ;; Track contributions
  }
)

;; Whitelist settings per launch
(define-map whitelist-settings
  { launch-id: uint }
  {
    enabled: bool,
    total-whitelisted: uint
  }
)

;; ========================================
;; Vesting Schedule Data Structures
;; ========================================

(define-data-var vesting-counter uint u0)

;; Vesting schedules for locked tokens
(define-map vesting-schedules
  { vesting-id: uint }
  {
    beneficiary: principal,
    token: principal,
    total-amount: uint,
    claimed-amount: uint,
    start-time: uint,
    cliff-duration: uint,      ;; Time before any tokens can be claimed
    vesting-duration: uint,    ;; Total vesting period after cliff
    created-by: principal,
    created-at: uint,
    revocable: bool,
    revoked: bool
  }
)

;; Track all vesting schedules for a beneficiary
(define-map beneficiary-vestings
  { beneficiary: principal }
  (list 20 uint)
)

;; Track vesting schedules by creator
(define-map creator-vestings
  { creator: principal }
  (list 20 uint)
)

;; ========================================
;; Token Lockup System
;; ========================================

(define-data-var lockup-counter uint u0)
(define-data-var contract-principal principal tx-sender)

;; Lockup type constants
(define-constant LOCKUP_TYPE_TEAM u1)
(define-constant LOCKUP_TYPE_ADVISORS u2)
(define-constant LOCKUP_TYPE_INVESTORS u3)
(define-constant LOCKUP_TYPE_TREASURY u4)

;; Token lockup schedules
(define-map token-lockups
  { lockup-id: uint }
  {
    token: principal,
    beneficiary: principal,
    creator: principal,
    lockup-type: uint,
    total-amount: uint,
    released-amount: uint,
    start-time: uint,
    cliff-duration: uint,
    release-duration: uint,
    release-interval: uint,  ;; Release tokens every X seconds
    last-release-time: uint,
    revocable: bool,
    revoked: bool,
    created-at: uint
  }
)

;; Track lockups by beneficiary
(define-map beneficiary-lockups
  { beneficiary: principal }
  (list 50 uint)
)

;; Track lockups by token
(define-map token-lockup-list
  { token: principal }
  (list 50 uint)
)

;; ========================================
;; Launch Insurance Pool System
;; ========================================

(define-data-var insurance-counter uint u0)
(define-data-var insurance-pool-balance uint u0)
(define-data-var claim-counter uint u0)
(define-data-var insurance-premium-bps uint u200) ;; 2% insurance premium
(define-data-var milestone-verification-period uint u604800) ;; 7 days

;; Launch insurance policies
(define-map launch-insurance
  { launch-id: uint }
  {
    coverage-amount: uint,
    premium-paid: uint,
    purchased-at: uint,
    expires-at: uint,
    active: bool,
    milestone-count: uint,
    milestones-met: uint,
    creator: principal
  }
)

;; Insurance claims
(define-map insurance-claims
  { launch-id: uint, claim-id: uint }
  {
    claimant: principal,
    claim-amount: uint,
    reason: (string-ascii 256),
    filed-at: uint,
    processed-at: uint,
    approved: bool,
    processed: bool,
    payout-amount: uint
  }
)

;; Milestone tracking for insured launches
(define-map launch-milestones
  { launch-id: uint, milestone-id: uint }
  {
    description: (string-ascii 256),
    target-date: uint,
    met: bool,
    verified-at: uint,
    verified-by: principal
  }
)

;; Contributor refund eligibility for failed launches
(define-map contributor-refunds
  { launch-id: uint, contributor: principal }
  {
    eligible-amount: uint,
    claimed: bool,
    claimed-at: uint
  }
)

;; Read-only functions

;; Get approved hash details
(define-read-only (get-approved-hash (hash (buff 32)))
  (map-get? approved-hashes { hash: hash })
)

;; Check if hash is approved
(define-read-only (is-hash-approved (hash (buff 32)))
  (is-some (get-approved-hash hash))
)

;; Get token listing
(define-read-only (get-token-listing (token principal))
  (map-get? token-listings { token: token })
)

;; Check if token is verified
(define-read-only (is-token-verified (token principal))
  (match (get-token-listing token)
    listing (get verified listing)
    false
  )
)

;; Get launch pool details
(define-read-only (get-launch-pool (launch-id uint))
  (map-get? launch-pools { launch-id: launch-id })
)

;; Get contribution for a launch
(define-read-only (get-contribution (launch-id uint) (contributor principal))
  (map-get? launch-contributions { launch-id: launch-id, contributor: contributor })
)

;; Calculate swap output (constant product formula)
(define-read-only (get-swap-quote (token principal) (stx-in uint) (is-buy bool))
  (match (get-token-listing token)
    listing
      (let (
          (stx-reserve (get stx-reserve listing))
          (token-reserve (get token-reserve listing))
          (fee-amount (/ (* stx-in SWAP_FEE_BPS) u10000))
          (amount-after-fee (- stx-in fee-amount))
        )
        (if is-buy
          ;; Buying tokens with STX
          (let ((new-stx-reserve (+ stx-reserve amount-after-fee)))
            (ok (- token-reserve (/ (* stx-reserve token-reserve) new-stx-reserve)))
          )
          ;; Selling tokens for STX
          (let ((new-token-reserve (+ token-reserve amount-after-fee)))
            (ok (- stx-reserve (/ (* stx-reserve token-reserve) new-token-reserve)))
          )
        )
      )
    (err ERR_POOL_NOT_FOUND)
  )
)

;; Get current block timestamp
(define-read-only (get-block-timestamp)
  (ok stacks-block-time)
)

;; Get protocol stats
(define-read-only (get-protocol-stats)
  {
    total-pools: (var-get total-pools),
    total-launches: (var-get total-launches),
    protocol-fees: (var-get protocol-fees-collected),
    paused: (var-get paused)
  }
)

;; Verify contract hash using Clarity 4 contract-hash?
(define-read-only (verify-contract-hash (token principal))
  (match (contract-hash? token)
    hash (ok hash)
    (err ERR_INVALID_HASH)
  )
)

;; Get whitelist status for a user
(define-read-only (get-whitelist-status (launch-id uint) (user principal))
  (map-get? launch-whitelist { launch-id: launch-id, user: user })
)

;; Check if user is whitelisted
(define-read-only (is-whitelisted (launch-id uint) (user principal))
  (is-some (get-whitelist-status launch-id user))
)

;; Get whitelist settings for launch
(define-read-only (get-whitelist-settings (launch-id uint))
  (default-to { enabled: false, total-whitelisted: u0 }
    (map-get? whitelist-settings { launch-id: launch-id })
  )
)

;; Check if launch requires whitelist
(define-read-only (is-whitelist-required (launch-id uint))
  (get enabled (get-whitelist-settings launch-id))
)

;; ========================================
;; Vesting Read-Only Functions
;; ========================================

;; Get vesting schedule details
(define-read-only (get-vesting-schedule (vesting-id uint))
  (map-get? vesting-schedules { vesting-id: vesting-id })
)

;; Calculate vested amount at current time
(define-read-only (calculate-vested-amount (vesting-id uint))
  (match (get-vesting-schedule vesting-id)
    schedule
      (let
        (
          (current-time stacks-block-time)
          (start (get start-time schedule))
          (cliff (get cliff-duration schedule))
          (duration (get vesting-duration schedule))
          (total (get total-amount schedule))
        )
        ;; Check if revoked
        (if (get revoked schedule)
          u0
          ;; Check if before cliff
          (if (< current-time (+ start cliff))
            u0
            ;; Check if fully vested
            (if (>= current-time (+ start cliff duration))
              total
              ;; Calculate proportional vesting
              (let
                (
                  (elapsed (- current-time (+ start cliff)))
                )
                (/ (* total elapsed) duration)
              )
            )
          )
        )
      )
    u0
  )
)

;; Get claimable amount
(define-read-only (get-claimable-amount (vesting-id uint))
  (match (get-vesting-schedule vesting-id)
    schedule
      (let
        (
          (vested (calculate-vested-amount vesting-id))
          (claimed (get claimed-amount schedule))
        )
        (if (>= vested claimed)
          (- vested claimed)
          u0
        )
      )
    u0
  )
)

;; Get beneficiary vesting schedules
(define-read-only (get-beneficiary-vestings (beneficiary principal))
  (default-to (list) (map-get? beneficiary-vestings { beneficiary: beneficiary }))
)

;; Get creator vesting schedules
(define-read-only (get-creator-vestings (creator principal))
  (default-to (list) (map-get? creator-vestings { creator: creator }))
)

;; Get comprehensive vesting info
(define-read-only (get-vesting-info (vesting-id uint))
  (match (get-vesting-schedule vesting-id)
    schedule
      (ok {
        schedule: schedule,
        vested-amount: (calculate-vested-amount vesting-id),
        claimable-amount: (get-claimable-amount vesting-id),
        remaining-amount: (- (get total-amount schedule) (get claimed-amount schedule))
      })
    ERR_VESTING_NOT_FOUND
  )
)

;; ========================================
;; Lockup Read-Only Functions
;; ========================================

;; Get lockup details
(define-read-only (get-lockup (lockup-id uint))
  (map-get? token-lockups { lockup-id: lockup-id })
)

;; Calculate releasable amount for a lockup
(define-read-only (calculate-releasable-amount (lockup-id uint))
  (match (get-lockup lockup-id)
    lockup
      (let
        (
          (current-time stacks-block-time)
          (start-time (get start-time lockup))
          (cliff-end (+ start-time (get cliff-duration lockup)))
          (release-end (+ start-time (get cliff-duration lockup) (get release-duration lockup)))
          (total (get total-amount lockup))
          (released (get released-amount lockup))
        )
        (if (get revoked lockup)
          u0
          (if (< current-time cliff-end)
            u0
            (if (>= current-time release-end)
              (- total released)
              (let
                (
                  (time-since-cliff (- current-time cliff-end))
                  (release-duration (get release-duration lockup))
                  (releasable-total (/ (* total time-since-cliff) release-duration))
                )
                (if (> releasable-total released)
                  (- releasable-total released)
                  u0))))))
    u0)
)

;; Get beneficiary lockups
(define-read-only (get-beneficiary-lockups (beneficiary principal))
  (default-to (list) (map-get? beneficiary-lockups { beneficiary: beneficiary }))
)

;; Get token lockups
(define-read-only (get-token-lockups (token principal))
  (default-to (list) (map-get? token-lockup-list { token: token }))
)

;; Get lockup info
(define-read-only (get-lockup-info (lockup-id uint))
  (match (get-lockup lockup-id)
    lockup
      (ok {
        lockup: lockup,
        releasable-amount: (calculate-releasable-amount lockup-id),
        remaining-locked: (- (get total-amount lockup) (get released-amount lockup)),
        is-revoked: (get revoked lockup),
        is-past-cliff: (>= stacks-block-time (+ (get start-time lockup) (get cliff-duration lockup)))
      })
    ERR_LOCKUP_NOT_FOUND)
)

;; ========================================
;; Insurance Read-Only Functions
;; ========================================

;; Get launch insurance
(define-read-only (get-launch-insurance (launch-id uint))
  (map-get? launch-insurance { launch-id: launch-id })
)

;; Get insurance claim
(define-read-only (get-insurance-claim (launch-id uint) (claim-id uint))
  (map-get? insurance-claims { launch-id: launch-id, claim-id: claim-id })
)

;; Get launch milestone
(define-read-only (get-launch-milestone (launch-id uint) (milestone-id uint))
  (map-get? launch-milestones { launch-id: launch-id, milestone-id: milestone-id })
)

;; Get contributor refund status
(define-read-only (get-contributor-refund (launch-id uint) (contributor principal))
  (map-get? contributor-refunds { launch-id: launch-id, contributor: contributor })
)

;; Calculate insurance premium
(define-read-only (calculate-insurance-premium (coverage-amount uint))
  (/ (* coverage-amount (var-get insurance-premium-bps)) u10000)
)

;; Check if launch has active insurance
(define-read-only (has-active-insurance (launch-id uint))
  (match (get-launch-insurance launch-id)
    insurance (and
      (get active insurance)
      (>= (get expires-at insurance) stacks-block-time))
    false)
)

;; Get insurance pool stats
(define-read-only (get-insurance-pool-stats)
  {
    pool-balance: (var-get insurance-pool-balance),
    total-policies: (var-get insurance-counter),
    total-claims: (var-get claim-counter),
    premium-bps: (var-get insurance-premium-bps)
  }
)

;; Private functions

;; Calculate and apply fees
(define-private (calculate-fees (amount uint))
  {
    swap-fee: (/ (* amount SWAP_FEE_BPS) u10000),
    protocol-fee: (/ (* amount PROTOCOL_FEE_BPS) u10000)
  }
)

;; Public functions

;; Admin: Add approved token template hash
(define-public (add-approved-hash (hash (buff 32)) (name (string-ascii 64)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    
    (map-set approved-hashes
      { hash: hash }
      {
        name: name,
        approved-at: stacks-block-time,
        approved-by: tx-sender
      }
    )
    
    (ok true)
  )
)

;; Admin: Remove approved hash
(define-public (remove-approved-hash (hash (buff 32)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (map-delete approved-hashes { hash: hash })
    (ok true)
  )
)

;; List a token (with hash verification)
(define-public (list-token (token <ft-trait>) (initial-stx uint) (initial-tokens uint))
  (let (
      (token-principal (contract-of token))
      (pool-id (+ (var-get total-pools) u1))
      ;; Verify contract hash using Clarity 4 contract-hash?
      (token-hash (unwrap! (contract-hash? token-principal) ERR_INVALID_HASH))
    )
    ;; Validations
    (asserts! (not (var-get paused)) ERR_NOT_AUTHORIZED)
    (asserts! (is-none (get-token-listing token-principal)) ERR_TOKEN_ALREADY_LISTED)
    (asserts! (> initial-stx u0) ERR_ZERO_AMOUNT)
    (asserts! (> initial-tokens u0) ERR_ZERO_AMOUNT)
    
    ;; Check if hash is from approved template
    (let ((is-verified (is-hash-approved token-hash)))
      
      ;; Collect listing fee
      (try! (stx-transfer? LISTING_FEE tx-sender CONTRACT_OWNER))
      
      ;; Transfer initial STX liquidity
      (try! (stx-transfer? initial-stx tx-sender (as-contract tx-sender)))
      
      ;; Transfer initial tokens
      (try! (contract-call? token transfer initial-tokens tx-sender (as-contract tx-sender) none))
      
      ;; Create listing
      (map-set token-listings
        { token: token-principal }
        {
          pool-id: pool-id,
          verified: is-verified,
          contract-hash: token-hash,
          listed-at: stacks-block-time,
          lister: tx-sender,
          stx-reserve: initial-stx,
          token-reserve: initial-tokens,
          total-fees-earned: u0
        }
      )
      
      (var-set total-pools pool-id)

      (print { event: "token-listed", pool-id: pool-id, token: token-principal, verified: is-verified, lister: tx-sender })

      (ok { pool-id: pool-id, verified: is-verified, hash: token-hash })
    )
  )
)

;; Swap STX for tokens (buy)
(define-public (buy-tokens (token <ft-trait>) (stx-amount uint) (min-tokens-out uint))
  (let (
      (token-principal (contract-of token))
      (listing (unwrap! (get-token-listing token-principal) ERR_POOL_NOT_FOUND))
      (fees (calculate-fees stx-amount))
      (stx-after-fee (- stx-amount (get swap-fee fees)))
      (stx-reserve (get stx-reserve listing))
      (token-reserve (get token-reserve listing))
      ;; Constant product: x * y = k
      (new-stx-reserve (+ stx-reserve stx-after-fee))
      (tokens-out (- token-reserve (/ (* stx-reserve token-reserve) new-stx-reserve)))
    )
    ;; Validations
    (asserts! (not (var-get paused)) ERR_NOT_AUTHORIZED)
    (asserts! (> stx-amount u0) ERR_ZERO_AMOUNT)
    (asserts! (>= tokens-out min-tokens-out) ERR_SLIPPAGE_TOO_HIGH)
    (asserts! (< tokens-out token-reserve) ERR_INSUFFICIENT_LIQUIDITY)
    
    ;; Use restrict-assets? to ensure safe token transfer (Clarity 4)
    ;; This will automatically rollback if post-conditions are violated
    
    ;; Transfer STX from buyer
    (try! (stx-transfer? stx-amount tx-sender (as-contract tx-sender)))
    
    ;; Transfer tokens to buyer
    (try! (as-contract (contract-call? token transfer tokens-out tx-sender tx-sender none)))
    
    ;; Update reserves
    (map-set token-listings
      { token: token-principal }
      (merge listing {
        stx-reserve: new-stx-reserve,
        token-reserve: (- token-reserve tokens-out),
        total-fees-earned: (+ (get total-fees-earned listing) (get swap-fee fees))
      })
    )
    
    ;; Collect protocol fee
    (var-set protocol-fees-collected (+ (var-get protocol-fees-collected) (get protocol-fee fees)))

    (print { event: "tokens-bought", token: token-principal, buyer: tx-sender, stx-in: stx-amount, tokens-out: tokens-out })

    (ok { tokens-received: tokens-out, fee-paid: (get swap-fee fees) })
  )
)

;; Swap tokens for STX (sell)
(define-public (sell-tokens (token <ft-trait>) (token-amount uint) (min-stx-out uint))
  (let (
      (token-principal (contract-of token))
      (listing (unwrap! (get-token-listing token-principal) ERR_POOL_NOT_FOUND))
      (stx-reserve (get stx-reserve listing))
      (token-reserve (get token-reserve listing))
      ;; Constant product formula
      (new-token-reserve (+ token-reserve token-amount))
      (stx-out-gross (- stx-reserve (/ (* stx-reserve token-reserve) new-token-reserve)))
      (fees (calculate-fees stx-out-gross))
      (stx-out (- stx-out-gross (get swap-fee fees)))
    )
    ;; Validations
    (asserts! (not (var-get paused)) ERR_NOT_AUTHORIZED)
    (asserts! (> token-amount u0) ERR_ZERO_AMOUNT)
    (asserts! (>= stx-out min-stx-out) ERR_SLIPPAGE_TOO_HIGH)
    (asserts! (< stx-out-gross stx-reserve) ERR_INSUFFICIENT_LIQUIDITY)
    
    ;; Transfer tokens from seller
    (try! (contract-call? token transfer token-amount tx-sender (as-contract tx-sender) none))
    
    ;; Transfer STX to seller
    (try! (as-contract (stx-transfer? stx-out tx-sender tx-sender)))
    
    ;; Update reserves
    (map-set token-listings
      { token: token-principal }
      (merge listing {
        stx-reserve: (- stx-reserve stx-out-gross),
        token-reserve: new-token-reserve,
        total-fees-earned: (+ (get total-fees-earned listing) (get swap-fee fees))
      })
    )
    
    ;; Collect protocol fee
    (var-set protocol-fees-collected (+ (var-get protocol-fees-collected) (get protocol-fee fees)))

    (print { event: "tokens-sold", token: token-principal, seller: tx-sender, tokens-in: token-amount, stx-out: stx-out })

    (ok { stx-received: stx-out, fee-paid: (get swap-fee fees) })
  )
)

;; Create a fair launch pool
(define-public (create-launch 
    (token <ft-trait>) 
    (tokens-for-sale uint) 
    (min-raise uint) 
    (max-raise uint))
  (let (
      (token-principal (contract-of token))
      (launch-id (+ (var-get total-launches) u1))
      (current-time stacks-block-time)
      ;; Verify token contract hash (Clarity 4)
      (token-hash (unwrap! (contract-hash? token-principal) ERR_INVALID_HASH))
    )
    ;; Validations
    (asserts! (not (var-get paused)) ERR_NOT_AUTHORIZED)
    (asserts! (> tokens-for-sale u0) ERR_ZERO_AMOUNT)
    (asserts! (> min-raise u0) ERR_ZERO_AMOUNT)
    (asserts! (>= max-raise min-raise) ERR_ZERO_AMOUNT)
    
    ;; Transfer tokens to contract
    (try! (contract-call? token transfer tokens-for-sale tx-sender (as-contract tx-sender) none))
    
    ;; Create launch pool
    (map-set launch-pools
      { launch-id: launch-id }
      {
        token: token-principal,
        creator: tx-sender,
        stx-raised: u0,
        tokens-for-sale: tokens-for-sale,
        min-raise: min-raise,
        max-raise: max-raise,
        start-time: current-time,
        end-time: (+ current-time LAUNCH_DURATION),
        finalized: false,
        successful: false
      }
    )
    
    (var-set total-launches launch-id)

    (print { event: "launch-created", launch-id: launch-id, token: token-principal, creator: tx-sender, tokens-for-sale: tokens-for-sale })

    (ok { launch-id: launch-id, ends-at: (+ current-time LAUNCH_DURATION) })
  )
)

;; Contribute to launch
(define-public (contribute-to-launch (launch-id uint) (stx-amount uint))
  (let (
      (launch (unwrap! (get-launch-pool launch-id) ERR_POOL_NOT_FOUND))
      (current-time stacks-block-time)
      (existing-contribution (default-to { amount: u0, claimed: false }
                              (get-contribution launch-id tx-sender)))
      (whitelist-config (get-whitelist-settings launch-id))
    )
    ;; Validations
    (asserts! (not (var-get paused)) ERR_NOT_AUTHORIZED)
    (asserts! (>= current-time (get start-time launch)) ERR_LAUNCH_NOT_ACTIVE)
    (asserts! (<= current-time (get end-time launch)) ERR_LAUNCH_ENDED)
    (asserts! (not (get finalized launch)) ERR_LAUNCH_ENDED)
    (asserts! (> stx-amount u0) ERR_ZERO_AMOUNT)

    ;; Check whitelist if enabled
    (if (get enabled whitelist-config)
      (let ((whitelist-entry (unwrap! (get-whitelist-status launch-id tx-sender) ERR_WHITELIST_REQUIRED)))
        ;; Verify user doesn't exceed their individual cap
        (asserts! (<= (+ (get contributed-amount whitelist-entry) stx-amount)
                     (get max-contribution whitelist-entry))
                 ERR_SLIPPAGE_TOO_HIGH)
        ;; Update whitelist contribution tracking
        (map-set launch-whitelist
          { launch-id: launch-id, user: tx-sender }
          (merge whitelist-entry {
            contributed-amount: (+ (get contributed-amount whitelist-entry) stx-amount)
          })
        )
      )
      true  ;; Whitelist not enabled, allow anyone
    )
    
    ;; Check max raise not exceeded
    (let ((new-total (+ (get stx-raised launch) stx-amount)))
      (asserts! (<= new-total (get max-raise launch)) ERR_SLIPPAGE_TOO_HIGH)
      
      ;; Transfer STX
      (try! (stx-transfer? stx-amount tx-sender (as-contract tx-sender)))
      
      ;; Update contribution
      (map-set launch-contributions
        { launch-id: launch-id, contributor: tx-sender }
        { 
          amount: (+ (get amount existing-contribution) stx-amount),
          claimed: false
        }
      )
      
      ;; Update launch pool
      (map-set launch-pools
        { launch-id: launch-id }
        (merge launch { stx-raised: new-total })
      )

      (print { event: "launch-contribution", launch-id: launch-id, contributor: tx-sender, amount: stx-amount, total-raised: new-total })

      (ok { total-contributed: (+ (get amount existing-contribution) stx-amount) })
    )
  )
)

;; Finalize launch (can be called by anyone after end time)
(define-public (finalize-launch (launch-id uint))
  (let (
      (launch (unwrap! (get-launch-pool launch-id) ERR_POOL_NOT_FOUND))
      (current-time stacks-block-time)
    )
    ;; Validations
    (asserts! (> current-time (get end-time launch)) ERR_LAUNCH_NOT_ACTIVE)
    (asserts! (not (get finalized launch)) ERR_LAUNCH_ENDED)
    
    (let ((is-successful (>= (get stx-raised launch) (get min-raise launch))))
      ;; Update launch status
      (map-set launch-pools
        { launch-id: launch-id }
        (merge launch {
          finalized: true,
          successful: is-successful
        })
      )
      
      ;; If successful, create liquidity pool
      ;; If failed, contributors can claim refunds via claim-from-launch

      (print { event: "launch-finalized", launch-id: launch-id, successful: is-successful, total-raised: (get stx-raised launch) })

      (ok { successful: is-successful, total-raised: (get stx-raised launch) })
    )
  )
)

;; Claim tokens or refund from launch
(define-public (claim-from-launch (launch-id uint) (token <ft-trait>))
  (let (
      (launch (unwrap! (get-launch-pool launch-id) ERR_POOL_NOT_FOUND))
      (contribution (unwrap! (get-contribution launch-id tx-sender) ERR_POOL_NOT_FOUND))
    )
    ;; Validations
    (asserts! (get finalized launch) ERR_LAUNCH_NOT_ACTIVE)
    (asserts! (not (get claimed contribution)) ERR_ALREADY_CLAIMED)
    (asserts! (is-eq (contract-of token) (get token launch)) ERR_TOKEN_NOT_VERIFIED)
    
    ;; Mark as claimed
    (map-set launch-contributions
      { launch-id: launch-id, contributor: tx-sender }
      (merge contribution { claimed: true })
    )
    
    (if (get successful launch)
      ;; Successful launch - distribute tokens proportionally
      (let (
          (user-share (/ (* (get amount contribution) (get tokens-for-sale launch))
                         (get stx-raised launch)))
        )
        (try! (as-contract (contract-call? token transfer user-share tx-sender tx-sender none)))
        (print { event: "launch-claim", launch-id: launch-id, claimer: tx-sender, tokens-received: user-share })
        (ok { tokens-received: user-share, refund: u0 })
      )
      ;; Failed launch - refund STX
      (begin
        (try! (as-contract (stx-transfer? (get amount contribution) tx-sender tx-sender)))
        (print { event: "launch-refund", launch-id: launch-id, claimer: tx-sender, refund: (get amount contribution) })
        (ok { tokens-received: u0, refund: (get amount contribution) })
      )
    )
  )
)

;; Admin: Toggle pause
(define-public (toggle-pause)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (var-set paused (not (var-get paused)))
    (ok (var-get paused))
  )
)

;; Admin: Withdraw protocol fees
(define-public (withdraw-protocol-fees (amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (asserts! (<= amount (var-get protocol-fees-collected)) ERR_INSUFFICIENT_LIQUIDITY)

    (var-set protocol-fees-collected (- (var-get protocol-fees-collected) amount))
    (try! (as-contract (stx-transfer? amount tx-sender CONTRACT_OWNER)))

    (ok amount)
  )
)

;; ========================================
;; Whitelist Management Functions
;; ========================================

;; Enable whitelist for a launch (creator only, must be before launch starts)
(define-public (enable-whitelist (launch-id uint))
  (let (
      (launch (unwrap! (get-launch-pool launch-id) ERR_POOL_NOT_FOUND))
      (current-time stacks-block-time)
    )
    ;; Validations
    (asserts! (is-eq tx-sender (get creator launch)) ERR_NOT_AUTHORIZED)
    (asserts! (< current-time (get start-time launch)) ERR_LAUNCH_NOT_ACTIVE)

    ;; Initialize whitelist settings
    (map-set whitelist-settings
      { launch-id: launch-id }
      { enabled: true, total-whitelisted: u0 }
    )

    (print {
      event: "whitelist-enabled",
      launch-id: launch-id,
      creator: tx-sender,
      timestamp: current-time
    })

    (ok true)
  )
)

;; Add user to whitelist (creator only)
(define-public (add-to-whitelist (launch-id uint) (user principal) (max-contribution uint))
  (let (
      (launch (unwrap! (get-launch-pool launch-id) ERR_POOL_NOT_FOUND))
      (settings (get-whitelist-settings launch-id))
      (current-time stacks-block-time)
    )
    ;; Validations
    (asserts! (is-eq tx-sender (get creator launch)) ERR_NOT_AUTHORIZED)
    (asserts! (get enabled settings) ERR_NOT_AUTHORIZED)
    (asserts! (< current-time (get start-time launch)) ERR_LAUNCH_NOT_ACTIVE)
    (asserts! (> max-contribution u0) ERR_ZERO_AMOUNT)
    (asserts! (is-none (get-whitelist-status launch-id user)) ERR_TOKEN_ALREADY_LISTED)

    ;; Add to whitelist
    (map-set launch-whitelist
      { launch-id: launch-id, user: user }
      {
        whitelisted-at: current-time,
        max-contribution: max-contribution,
        contributed-amount: u0
      }
    )

    ;; Update total whitelisted count
    (map-set whitelist-settings
      { launch-id: launch-id }
      (merge settings { total-whitelisted: (+ (get total-whitelisted settings) u1) })
    )

    (print {
      event: "user-whitelisted",
      launch-id: launch-id,
      user: user,
      max-contribution: max-contribution,
      timestamp: current-time
    })

    (ok true)
  )
)

;; Batch add users to whitelist
(define-public (batch-add-to-whitelist
    (launch-id uint)
    (users (list 50 { user: principal, max-contribution: uint })))
  (let (
      (launch (unwrap! (get-launch-pool launch-id) ERR_POOL_NOT_FOUND))
      (settings (get-whitelist-settings launch-id))
      (current-time stacks-block-time)
    )
    ;; Validations
    (asserts! (is-eq tx-sender (get creator launch)) ERR_NOT_AUTHORIZED)
    (asserts! (get enabled settings) ERR_NOT_AUTHORIZED)
    (asserts! (< current-time (get start-time launch)) ERR_LAUNCH_NOT_ACTIVE)

    ;; Process all users
    (fold process-whitelist-addition users (ok { launch-id: launch-id, count: u0 }))
  )
)

;; Helper function to add single user in batch
(define-private (process-whitelist-addition
    (user-info { user: principal, max-contribution: uint })
    (previous-result (response { launch-id: uint, count: uint } uint)))
  (match previous-result
    success
      (let (
          (launch-id (get launch-id success))
          (current-time stacks-block-time)
        )
        ;; Add to whitelist if not already present
        (if (is-none (get-whitelist-status launch-id (get user user-info)))
          (begin
            (map-set launch-whitelist
              { launch-id: launch-id, user: (get user user-info) }
              {
                whitelisted-at: current-time,
                max-contribution: (get max-contribution user-info),
                contributed-amount: u0
              }
            )
            (ok { launch-id: launch-id, count: (+ (get count success) u1) })
          )
          (ok success)  ;; Skip if already whitelisted
        )
      )
    error (err error)
  )
)

;; Remove user from whitelist (creator only, before launch starts)
(define-public (remove-from-whitelist (launch-id uint) (user principal))
  (let (
      (launch (unwrap! (get-launch-pool launch-id) ERR_POOL_NOT_FOUND))
      (settings (get-whitelist-settings launch-id))
      (current-time stacks-block-time)
    )
    ;; Validations
    (asserts! (is-eq tx-sender (get creator launch)) ERR_NOT_AUTHORIZED)
    (asserts! (get enabled settings) ERR_NOT_AUTHORIZED)
    (asserts! (< current-time (get start-time launch)) ERR_LAUNCH_NOT_ACTIVE)
    (asserts! (is-some (get-whitelist-status launch-id user)) ERR_POOL_NOT_FOUND)

    ;; Remove from whitelist
    (map-delete launch-whitelist { launch-id: launch-id, user: user })

    ;; Update total whitelisted count
    (map-set whitelist-settings
      { launch-id: launch-id }
      (merge settings { total-whitelisted: (- (get total-whitelisted settings) u1) })
    )

    (print {
      event: "user-removed-from-whitelist",
      launch-id: launch-id,
      user: user,
      timestamp: current-time
    })

    (ok true)
  )
)

;; ========================================
;; Vesting Schedule Public Functions
;; ========================================

;; Create vesting schedule for token lock
(define-public (create-vesting-schedule
  (beneficiary principal)
  (token <ft-trait>)
  (amount uint)
  (cliff-duration uint)
  (vesting-duration uint)
  (revocable bool))
  (let
    (
      (vesting-id (var-get vesting-counter))
      (current-time stacks-block-time)
      (token-principal (contract-of token))
      (beneficiary-list (get-beneficiary-vestings beneficiary))
      (creator-list (get-creator-vestings tx-sender))
    )
    ;; Validations
    (asserts! (> amount u0) ERR_ZERO_AMOUNT)
    (asserts! (> vesting-duration u0) ERR_INVALID_VESTING_SCHEDULE)

    ;; Transfer tokens to contract for vesting
    (try! (contract-call? token transfer amount tx-sender (as-contract tx-sender) none))

    ;; Create vesting schedule
    (map-set vesting-schedules
      { vesting-id: vesting-id }
      {
        beneficiary: beneficiary,
        token: token-principal,
        total-amount: amount,
        claimed-amount: u0,
        start-time: current-time,
        cliff-duration: cliff-duration,
        vesting-duration: vesting-duration,
        created-by: tx-sender,
        created-at: current-time,
        revocable: revocable,
        revoked: false
      }
    )

    ;; Track vesting for beneficiary
    (map-set beneficiary-vestings
      { beneficiary: beneficiary }
      (unwrap! (as-max-len? (append beneficiary-list vesting-id) u20) ERR_INVALID_VESTING_SCHEDULE)
    )

    ;; Track vesting for creator
    (map-set creator-vestings
      { creator: tx-sender }
      (unwrap! (as-max-len? (append creator-list vesting-id) u20) ERR_INVALID_VESTING_SCHEDULE)
    )

    ;; Increment counter
    (var-set vesting-counter (+ vesting-id u1))

    ;; Emit Chainhook event
    (print {
      event: "vesting-created",
      vesting-id: vesting-id,
      beneficiary: beneficiary,
      token: token-principal,
      amount: amount,
      cliff-duration: cliff-duration,
      vesting-duration: vesting-duration,
      revocable: revocable,
      created-by: tx-sender,
      timestamp: current-time
    })

    (ok vesting-id)
  )
)

;; Claim vested tokens
(define-public (claim-vested-tokens (vesting-id uint) (token <ft-trait>))
  (let
    (
      (schedule (unwrap! (get-vesting-schedule vesting-id) ERR_VESTING_NOT_FOUND))
      (claimable (get-claimable-amount vesting-id))
      (current-time stacks-block-time)
      (token-principal (contract-of token))
    )
    ;; Validations
    (asserts! (is-eq tx-sender (get beneficiary schedule)) ERR_NOT_AUTHORIZED)
    (asserts! (is-eq token-principal (get token schedule)) ERR_TOKEN_NOT_VERIFIED)
    (asserts! (> claimable u0) ERR_NO_TOKENS_AVAILABLE)
    (asserts! (not (get revoked schedule)) ERR_VESTING_NOT_FOUND)

    ;; Update claimed amount
    (map-set vesting-schedules
      { vesting-id: vesting-id }
      (merge schedule {
        claimed-amount: (+ (get claimed-amount schedule) claimable)
      })
    )

    ;; Transfer tokens to beneficiary
    (try! (as-contract (contract-call? token transfer claimable tx-sender (get beneficiary schedule) none)))

    ;; Emit Chainhook event
    (print {
      event: "tokens-claimed",
      vesting-id: vesting-id,
      beneficiary: (get beneficiary schedule),
      amount-claimed: claimable,
      total-claimed: (+ (get claimed-amount schedule) claimable),
      remaining: (- (get total-amount schedule) (+ (get claimed-amount schedule) claimable)),
      timestamp: current-time
    })

    (ok claimable)
  )
)

;; Revoke vesting schedule (only if revocable)
(define-public (revoke-vesting (vesting-id uint) (token <ft-trait>))
  (let
    (
      (schedule (unwrap! (get-vesting-schedule vesting-id) ERR_VESTING_NOT_FOUND))
      (vested (calculate-vested-amount vesting-id))
      (claimed (get claimed-amount schedule))
      (claimable (get-claimable-amount vesting-id))
      (unvested (- (get total-amount schedule) vested))
      (current-time stacks-block-time)
      (token-principal (contract-of token))
    )
    ;; Validations
    (asserts! (is-eq tx-sender (get created-by schedule)) ERR_NOT_AUTHORIZED)
    (asserts! (get revocable schedule) ERR_NOT_AUTHORIZED)
    (asserts! (not (get revoked schedule)) ERR_VESTING_NOT_FOUND)
    (asserts! (is-eq token-principal (get token schedule)) ERR_TOKEN_NOT_VERIFIED)

    ;; Mark as revoked
    (map-set vesting-schedules
      { vesting-id: vesting-id }
      (merge schedule { revoked: true })
    )

    ;; Return unvested tokens to creator
    (if (> unvested u0)
      (try! (as-contract (contract-call? token transfer unvested tx-sender (get created-by schedule) none)))
      true
    )

    ;; Transfer any claimable tokens to beneficiary
    (if (> claimable u0)
      (begin
        (map-set vesting-schedules
          { vesting-id: vesting-id }
          (merge schedule {
            claimed-amount: (+ claimed claimable),
            revoked: true
          })
        )
        (try! (as-contract (contract-call? token transfer claimable tx-sender (get beneficiary schedule) none)))
      )
      true
    )

    ;; Emit Chainhook event
    (print {
      event: "vesting-revoked",
      vesting-id: vesting-id,
      beneficiary: (get beneficiary schedule),
      unvested-returned: unvested,
      vested-transferred: claimable,
      revoked-by: tx-sender,
      timestamp: current-time
    })

    (ok { unvested-returned: unvested, vested-transferred: claimable })
  )
)

;; ========================================
;; Token Lockup Public Functions
;; ========================================

;; Create token lockup
(define-public (create-lockup
  (token <ft-trait>)
  (beneficiary principal)
  (lockup-type uint)
  (amount uint)
  (cliff-duration uint)
  (release-duration uint)
  (release-interval uint)
  (revocable bool))
  (let
    (
      (lockup-id (+ (var-get lockup-counter) u1))
      (current-time stacks-block-time)
      (existing-lockups (get-beneficiary-lockups beneficiary))
      (token-lockups (get-token-lockups (contract-of token)))
    )
    ;; Validations
    (asserts! (> amount u0) ERR_ZERO_AMOUNT)
    (asserts! (>= cliff-duration u0) ERR_INVALID_LOCKUP_DURATION)
    (asserts! (> release-duration u0) ERR_INVALID_LOCKUP_DURATION)
    (asserts! (> release-interval u0) ERR_INVALID_LOCKUP_DURATION)
    (asserts! (<= lockup-type LOCKUP_TYPE_TREASURY) ERR_INVALID_LOCKUP_DURATION)

    ;; Transfer tokens to contract
    (try! (contract-call? token transfer amount tx-sender (var-get contract-principal) none))

    ;; Create lockup record
    (map-set token-lockups
      { lockup-id: lockup-id }
      {
        token: (contract-of token),
        beneficiary: beneficiary,
        creator: tx-sender,
        lockup-type: lockup-type,
        total-amount: amount,
        released-amount: u0,
        start-time: current-time,
        cliff-duration: cliff-duration,
        release-duration: release-duration,
        release-interval: release-interval,
        last-release-time: current-time,
        revocable: revocable,
        revoked: false,
        created-at: current-time
      }
    )

    ;; Update beneficiary lockups list
    (match (as-max-len? (append existing-lockups lockup-id) u50)
      new-list (map-set beneficiary-lockups { beneficiary: beneficiary } new-list)
      false)

    ;; Update token lockups list
    (match (as-max-len? (append token-lockups lockup-id) u50)
      new-list (map-set token-lockup-list { token: (contract-of token) } new-list)
      false)

    (var-set lockup-counter lockup-id)

    ;; Emit Chainhook event
    (print {
      event: "lockup-created",
      lockup-id: lockup-id,
      token: (contract-of token),
      beneficiary: beneficiary,
      creator: tx-sender,
      lockup-type: lockup-type,
      amount: amount,
      cliff-duration: cliff-duration,
      release-duration: release-duration,
      revocable: revocable,
      timestamp: current-time
    })

    (ok lockup-id)
  )
)

;; Release tokens from lockup
(define-public (release-lockup (lockup-id uint) (token <ft-trait>))
  (let
    (
      (lockup (unwrap! (get-lockup lockup-id) ERR_LOCKUP_NOT_FOUND))
      (releasable (calculate-releasable-amount lockup-id))
      (current-time stacks-block-time)
    )
    ;; Validations
    (asserts! (is-eq (get beneficiary lockup) tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (not (get revoked lockup)) ERR_LOCKUP_NOT_FOUND)
    (asserts! (> releasable u0) ERR_NO_TOKENS_AVAILABLE)
    (asserts! (is-eq (get token lockup) (contract-of token)) ERR_TOKEN_NOT_VERIFIED)

    ;; Transfer tokens to beneficiary
    (try! (as-contract (contract-call? token transfer releasable tx-sender (get beneficiary lockup) none)))

    ;; Update lockup record
    (map-set token-lockups
      { lockup-id: lockup-id }
      (merge lockup {
        released-amount: (+ (get released-amount lockup) releasable),
        last-release-time: current-time
      })
    )

    ;; Emit Chainhook event
    (print {
      event: "lockup-released",
      lockup-id: lockup-id,
      beneficiary: (get beneficiary lockup),
      amount-released: releasable,
      total-released: (+ (get released-amount lockup) releasable),
      remaining-locked: (- (get total-amount lockup) (+ (get released-amount lockup) releasable)),
      timestamp: current-time
    })

    (ok releasable)
  )
)

;; Revoke lockup (only if revocable and by creator)
(define-public (revoke-lockup (lockup-id uint) (token <ft-trait>))
  (let
    (
      (lockup (unwrap! (get-lockup lockup-id) ERR_LOCKUP_NOT_FOUND))
      (releasable (calculate-releasable-amount lockup-id))
      (unreleased (- (get total-amount lockup) (get released-amount lockup)))
      (current-time stacks-block-time)
    )
    ;; Validations
    (asserts! (is-eq (get creator lockup) tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (get revocable lockup) ERR_NOT_AUTHORIZED)
    (asserts! (not (get revoked lockup)) ERR_LOCKUP_NOT_FOUND)
    (asserts! (is-eq (get token lockup) (contract-of token)) ERR_TOKEN_NOT_VERIFIED)

    ;; Transfer releasable tokens to beneficiary
    (if (> releasable u0)
      (try! (as-contract (contract-call? token transfer releasable tx-sender (get beneficiary lockup) none)))
      true)

    ;; Return unreleased tokens to creator
    (let ((to-return (- unreleased releasable)))
      (if (> to-return u0)
        (try! (as-contract (contract-call? token transfer to-return tx-sender (get creator lockup) none)))
        true))

    ;; Mark lockup as revoked
    (map-set token-lockups
      { lockup-id: lockup-id }
      (merge lockup {
        revoked: true,
        released-amount: (+ (get released-amount lockup) releasable)
      })
    )

    ;; Emit Chainhook event
    (print {
      event: "lockup-revoked",
      lockup-id: lockup-id,
      beneficiary: (get beneficiary lockup),
      releasable-transferred: releasable,
      unreleased-returned: (- unreleased releasable),
      revoked-by: tx-sender,
      timestamp: current-time
    })

    (ok { releasable-transferred: releasable, unreleased-returned: (- unreleased releasable) })
  )
)

;; Batch create lockups for multiple beneficiaries
(define-public (batch-create-lockups
  (token <ft-trait>)
  (lockups (list 20 {
    beneficiary: principal,
    lockup-type: uint,
    amount: uint,
    cliff-duration: uint,
    release-duration: uint,
    release-interval: uint,
    revocable: bool
  })))
  (let
    (
      (results (map create-single-lockup-entry lockups))
    )
    (ok (len results))
  )
)

;; Helper for batch creation
(define-private (create-single-lockup-entry (entry {
  beneficiary: principal,
  lockup-type: uint,
  amount: uint,
  cliff-duration: uint,
  release-duration: uint,
  release-interval: uint,
  revocable: bool
}))
  (let
    (
      (lockup-id (+ (var-get lockup-counter) u1))
      (current-time stacks-block-time)
    )
    (map-set token-lockups
      { lockup-id: lockup-id }
      {
        token: tx-sender,  ;; This would need token principal from context
        beneficiary: (get beneficiary entry),
        creator: tx-sender,
        lockup-type: (get lockup-type entry),
        total-amount: (get amount entry),
        released-amount: u0,
        start-time: current-time,
        cliff-duration: (get cliff-duration entry),
        release-duration: (get release-duration entry),
        release-interval: (get release-interval entry),
        last-release-time: current-time,
        revocable: (get revocable entry),
        revoked: false,
        created-at: current-time
      }
    )
    (var-set lockup-counter lockup-id)
    lockup-id
  )
)

;; ========================================
;; Launch Insurance Public Functions
;; ========================================

;; Purchase insurance for a launch
(define-public (purchase-launch-insurance (launch-id uint) (coverage-amount uint) (milestone-count uint))
  (let
    (
      (launch (unwrap! (get-launch-pool launch-id) ERR_POOL_NOT_FOUND))
      (premium (calculate-insurance-premium coverage-amount))
      (current-time stacks-block-time)
      (expiry-time (+ current-time (* u30 u86400))) ;; 30 days
    )
    (asserts! (is-eq tx-sender (get creator launch)) ERR_NOT_AUTHORIZED)
    (asserts! (is-none (get-launch-insurance launch-id)) ERR_INSURANCE_EXISTS)
    (asserts! (> coverage-amount u0) ERR_INVALID_INSURANCE)
    (asserts! (> milestone-count u0) ERR_INVALID_INSURANCE)
    (asserts! (<= milestone-count u10) ERR_INVALID_INSURANCE)
    
    ;; Transfer premium to contract
    (unwrap! (stx-transfer? premium tx-sender (var-get contract-principal)) ERR_INSUFFICIENT_LIQUIDITY)
    
    ;; Create insurance policy
    (map-set launch-insurance
      { launch-id: launch-id }
      {
        coverage-amount: coverage-amount,
        premium-paid: premium,
        purchased-at: current-time,
        expires-at: expiry-time,
        active: true,
        milestone-count: milestone-count,
        milestones-met: u0,
        creator: tx-sender
      }
    )
    
    (var-set insurance-pool-balance (+ (var-get insurance-pool-balance) premium))
    (var-set insurance-counter (+ (var-get insurance-counter) u1))
    
    (print {
      event: "insurance-purchased",
      launch-id: launch-id,
      coverage-amount: coverage-amount,
      premium-paid: premium,
      milestone-count: milestone-count,
      expires-at: expiry-time,
      timestamp: current-time
    })
    
    (ok true)
  )
)

;; Add milestone for insured launch
(define-public (add-launch-milestone (launch-id uint) (milestone-id uint) (description (string-ascii 256)) (target-date uint))
  (let
    (
      (insurance (unwrap! (get-launch-insurance launch-id) ERR_INSURANCE_NOT_FOUND))
    )
    (asserts! (is-eq tx-sender (get creator insurance)) ERR_NOT_AUTHORIZED)
    (asserts! (get active insurance) ERR_INSURANCE_NOT_FOUND)
    (asserts! (< milestone-id (get milestone-count insurance)) ERR_INVALID_INSURANCE)
    (asserts! (is-none (get-launch-milestone launch-id milestone-id)) ERR_INSURANCE_EXISTS)
    (asserts! (> target-date stacks-block-time) ERR_INVALID_INSURANCE)
    
    (map-set launch-milestones
      { launch-id: launch-id, milestone-id: milestone-id }
      {
        description: description,
        target-date: target-date,
        met: false,
        verified-at: u0,
        verified-by: tx-sender
      }
    )
    
    (print {
      event: "milestone-added",
      launch-id: launch-id,
      milestone-id: milestone-id,
      description: description,
      target-date: target-date,
      timestamp: stacks-block-time
    })
    
    (ok true)
  )
)

;; Verify milestone completion (admin only)
(define-public (verify-milestone (launch-id uint) (milestone-id uint) (met bool))
  (let
    (
      (insurance (unwrap! (get-launch-insurance launch-id) ERR_INSURANCE_NOT_FOUND))
      (milestone (unwrap! (get-launch-milestone launch-id milestone-id) ERR_CLAIM_NOT_FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (asserts! (not (get met milestone)) ERR_INSURANCE_EXISTS)
    
    (map-set launch-milestones
      { launch-id: launch-id, milestone-id: milestone-id }
      (merge milestone {
        met: met,
        verified-at: stacks-block-time,
        verified-by: tx-sender
      })
    )
    
    ;; Update insurance milestones met count
    (if met
      (map-set launch-insurance
        { launch-id: launch-id }
        (merge insurance {
          milestones-met: (+ (get milestones-met insurance) u1)
        }))
      true)
    
    (print {
      event: "milestone-verified",
      launch-id: launch-id,
      milestone-id: milestone-id,
      met: met,
      milestones-met: (if met (+ (get milestones-met insurance) u1) (get milestones-met insurance)),
      timestamp: stacks-block-time
    })
    
    (ok true)
  )
)

;; File insurance claim for failed launch
(define-public (file-insurance-claim (launch-id uint) (claim-amount uint) (reason (string-ascii 256)))
  (let
    (
      (launch (unwrap! (get-launch-pool launch-id) ERR_POOL_NOT_FOUND))
      (contribution (unwrap! (get-launch-contribution launch-id tx-sender) ERR_POOL_NOT_FOUND))
      (claim-id (var-get claim-counter))
    )
    (asserts! (has-active-insurance launch-id) ERR_INSURANCE_NOT_FOUND)
    (asserts! (> claim-amount u0) ERR_INVALID_INSURANCE)
    (asserts! (>= (get amount contribution) claim-amount) ERR_INVALID_INSURANCE)
    (asserts! (is-none (get-insurance-claim launch-id claim-id)) ERR_CLAIM_EXISTS)
    
    (map-set insurance-claims
      { launch-id: launch-id, claim-id: claim-id }
      {
        claimant: tx-sender,
        claim-amount: claim-amount,
        reason: reason,
        filed-at: stacks-block-time,
        processed-at: u0,
        approved: false,
        processed: false,
        payout-amount: u0
      }
    )
    
    (var-set claim-counter (+ claim-id u1))
    
    (print {
      event: "insurance-claim-filed",
      launch-id: launch-id,
      claim-id: claim-id,
      claimant: tx-sender,
      claim-amount: claim-amount,
      reason: reason,
      timestamp: stacks-block-time
    })
    
    (ok claim-id)
  )
)

;; Process insurance claim (admin only)
(define-public (process-insurance-claim (launch-id uint) (claim-id uint) (approved bool))
  (let
    (
      (insurance (unwrap! (get-launch-insurance launch-id) ERR_INSURANCE_NOT_FOUND))
      (claim (unwrap! (get-insurance-claim launch-id claim-id) ERR_CLAIM_NOT_FOUND))
      (payout (if approved (get claim-amount claim) u0))
      (pool-balance (var-get insurance-pool-balance))
    )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (asserts! (not (get processed claim)) ERR_INSURANCE_EXISTS)
    (asserts! (>= pool-balance payout) ERR_INSUFFICIENT_LIQUIDITY)
    
    (map-set insurance-claims
      { launch-id: launch-id, claim-id: claim-id }
      (merge claim {
        approved: approved,
        processed: true,
        processed-at: stacks-block-time,
        payout-amount: payout
      })
    )
    
    (if approved
      (begin
        ;; Transfer payout to claimant
        (unwrap! (stx-transfer? payout (var-get contract-principal) (get claimant claim)) ERR_INSUFFICIENT_LIQUIDITY)
        (var-set insurance-pool-balance (- pool-balance payout)))
      true)
    
    (print {
      event: "insurance-claim-processed",
      launch-id: launch-id,
      claim-id: claim-id,
      claimant: (get claimant claim),
      approved: approved,
      payout-amount: payout,
      timestamp: stacks-block-time
    })
    
    (ok payout)
  )
)

;; Enable contributor refunds for failed launch
(define-public (enable-contributor-refunds (launch-id uint))
  (let
    (
      (insurance (unwrap! (get-launch-insurance launch-id) ERR_INSURANCE_NOT_FOUND))
      (launch (unwrap! (get-launch-pool launch-id) ERR_POOL_NOT_FOUND))
      (milestone-success-rate (/ (* (get milestones-met insurance) u100) (get milestone-count insurance)))
    )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (asserts! (get active insurance) ERR_INSURANCE_NOT_FOUND)
    ;; Require less than 50% milestones met to enable refunds
    (asserts! (< milestone-success-rate u50) ERR_MILESTONE_NOT_MET)
    
    ;; Mark insurance as inactive
    (map-set launch-insurance
      { launch-id: launch-id }
      (merge insurance { active: false })
    )
    
    (print {
      event: "contributor-refunds-enabled",
      launch-id: launch-id,
      milestone-success-rate: milestone-success-rate,
      timestamp: stacks-block-time
    })
    
    (ok true)
  )
)

;; Claim contributor refund for failed launch
(define-public (claim-contributor-refund (launch-id uint))
  (let
    (
      (contribution (unwrap! (get-launch-contribution launch-id tx-sender) ERR_POOL_NOT_FOUND))
      (insurance (unwrap! (get-launch-insurance launch-id) ERR_INSURANCE_NOT_FOUND))
      (refund-amount (get amount contribution))
    )
    (asserts! (not (get active insurance)) ERR_INSURANCE_NOT_FOUND)
    (asserts! (not (get claimed contribution)) ERR_ALREADY_CLAIMED)
    (asserts! (> refund-amount u0) ERR_ZERO_AMOUNT)
    
    ;; Transfer refund to contributor
    (unwrap! (stx-transfer? refund-amount (var-get contract-principal) tx-sender) ERR_INSUFFICIENT_LIQUIDITY)
    
    ;; Mark contribution as claimed
    (map-set launch-contributions
      { launch-id: launch-id, contributor: tx-sender }
      (merge contribution { claimed: true })
    )
    
    ;; Record refund
    (map-set contributor-refunds
      { launch-id: launch-id, contributor: tx-sender }
      {
        eligible-amount: refund-amount,
        claimed: true,
        claimed-at: stacks-block-time
      }
    )
    
    (print {
      event: "contributor-refund-claimed",
      launch-id: launch-id,
      contributor: tx-sender,
      refund-amount: refund-amount,
      timestamp: stacks-block-time
    })
    
    (ok refund-amount)
  )
)

;; Admin: Update insurance parameters
(define-public (set-insurance-params (premium-bps uint) (verification-period uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (asserts! (<= premium-bps u1000) ERR_INVALID_INSURANCE) ;; Max 10%
    (asserts! (> verification-period u0) ERR_INVALID_INSURANCE)
    
    (var-set insurance-premium-bps premium-bps)
    (var-set milestone-verification-period verification-period)
    
    (print {
      event: "insurance-params-updated",
      premium-bps: premium-bps,
      verification-period: verification-period,
      timestamp: stacks-block-time
    })
    
    (ok true)
  )
)

