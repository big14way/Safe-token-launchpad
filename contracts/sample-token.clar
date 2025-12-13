;; Sample SIP-010 Token for Testing
;; This is a standard token template that would be hash-approved

(impl-trait .sip-010-trait.sip-010-trait)

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_INSUFFICIENT_BALANCE (err u101))

;; Token metadata
(define-constant TOKEN_NAME "Safe Launch Token")
(define-constant TOKEN_SYMBOL "SLT")
(define-constant TOKEN_DECIMALS u6)
(define-constant INITIAL_SUPPLY u1000000000000) ;; 1 million tokens with 6 decimals

;; Data Variables
(define-data-var total-supply uint INITIAL_SUPPLY)

;; Token balances
(define-map balances
  { account: principal }
  { balance: uint }
)

;; Initialize deployer balance
(map-set balances { account: CONTRACT_OWNER } { balance: INITIAL_SUPPLY })

;; SIP-010 Functions

(define-public (transfer (amount uint) (sender principal) (recipient principal) (memo (optional (buff 34))))
  (begin
    (asserts! (is-eq tx-sender sender) ERR_NOT_AUTHORIZED)
    (let (
        (sender-balance (get-balance-uint sender))
      )
      (asserts! (>= sender-balance amount) ERR_INSUFFICIENT_BALANCE)
      
      ;; Update balances
      (map-set balances { account: sender } { balance: (- sender-balance amount) })
      (map-set balances { account: recipient } 
        { balance: (+ (get-balance-uint recipient) amount) })
      
      ;; Print memo if provided
      (match memo
        memo-data (print memo-data)
        true
      )
      
      (ok true)
    )
  )
)

(define-read-only (get-name)
  (ok TOKEN_NAME)
)

(define-read-only (get-symbol)
  (ok TOKEN_SYMBOL)
)

(define-read-only (get-decimals)
  (ok TOKEN_DECIMALS)
)

(define-read-only (get-balance (account principal))
  (ok (get-balance-uint account))
)

(define-read-only (get-total-supply)
  (ok (var-get total-supply))
)

(define-read-only (get-token-uri)
  (ok (some u"https://example.com/token-metadata.json"))
)

;; Helper function
(define-private (get-balance-uint (account principal))
  (default-to u0 (get balance (map-get? balances { account: account })))
)

;; Mint function (for testing only)
(define-public (mint (amount uint) (recipient principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (var-set total-supply (+ (var-get total-supply) amount))
    (map-set balances { account: recipient } 
      { balance: (+ (get-balance-uint recipient) amount) })
    (ok true)
  )
)
