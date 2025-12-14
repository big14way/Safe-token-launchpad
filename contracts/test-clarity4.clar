;; Test Clarity 4 Features
;; Minimal contract to test which Clarity 4 features work

(define-constant CONTRACT_OWNER tx-sender)

;; Test stacks-block-time
(define-read-only (get-block-time)
  (ok stacks-block-time)
)

;; Test contract-hash?
(define-read-only (test-contract-hash (contract principal))
  (contract-hash? contract)
)

;; Test basic function
(define-public (test-function)
  (ok true)
)
