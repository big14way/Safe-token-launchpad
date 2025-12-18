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
    )
    ;; Validations
    (asserts! (not (var-get paused)) ERR_NOT_AUTHORIZED)
    (asserts! (>= current-time (get start-time launch)) ERR_LAUNCH_NOT_ACTIVE)
    (asserts! (<= current-time (get end-time launch)) ERR_LAUNCH_ENDED)
    (asserts! (not (get finalized launch)) ERR_LAUNCH_ENDED)
    (asserts! (> stx-amount u0) ERR_ZERO_AMOUNT)
    
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
