;; Document Timestamp Anchor Contract
;; Provides legal proof of document existence and timestamps for intellectual property

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-exists (err u102))
(define-constant err-unauthorized (err u103))
(define-constant err-invalid-hash (err u104))
(define-constant err-invalid-transfer (err u105))

;; Data Variables
(define-data-var total-documents uint u0)
(define-data-var total-verifications uint u0)

;; Data Maps
(define-map documents
  { document-hash: (buff 32) }
  {
    owner: principal,
    timestamp: uint,
    block-height: uint,
    description: (string-ascii 256),
    verified: bool,
    verification-count: uint
  }
)

(define-map document-ownership-history
  { document-hash: (buff 32), index: uint }
  {
    previous-owner: principal,
    new-owner: principal,
    transfer-timestamp: uint,
    transfer-block-height: uint
  }
)

(define-map ownership-transfer-count
  { document-hash: (buff 32) }
  { count: uint }
)

(define-map user-documents
  { owner: principal, index: uint }
  { document-hash: (buff 32) }
)

(define-map user-document-count
  { owner: principal }
  { count: uint }
)

(define-map verifier-records
  { verifier: principal, document-hash: (buff 32) }
  {
    verified-at: uint,
    verified-block: uint,
    verification-note: (string-ascii 256)
  }
)

;; Private Functions
(define-private (is-valid-hash (hash (buff 32)))
  (> (len hash) u0)
)

;; Read-Only Functions
(define-read-only (get-document-info (document-hash (buff 32)))
  (ok (map-get? documents { document-hash: document-hash }))
)

(define-read-only (get-document-owner (document-hash (buff 32)))
  (ok (get owner (default-to 
    { owner: contract-owner, timestamp: u0, block-height: u0, description: "", verified: false, verification-count: u0 }
    (map-get? documents { document-hash: document-hash })
  )))
)

(define-read-only (get-total-documents)
  (ok (var-get total-documents))
)

(define-read-only (get-total-verifications)
  (ok (var-get total-verifications))
)

(define-read-only (get-user-document-count (user principal))
  (ok (get count (default-to { count: u0 } (map-get? user-document-count { owner: user }))))
)

(define-read-only (get-user-document-at-index (user principal) (index uint))
  (ok (map-get? user-documents { owner: user, index: index }))
)

(define-read-only (get-ownership-transfer-count (document-hash (buff 32)))
  (ok (get count (default-to { count: u0 } (map-get? ownership-transfer-count { document-hash: document-hash }))))
)

(define-read-only (get-ownership-history (document-hash (buff 32)) (index uint))
  (ok (map-get? document-ownership-history { document-hash: document-hash, index: index }))
)

(define-read-only (get-verifier-record (verifier principal) (document-hash (buff 32)))
  (ok (map-get? verifier-records { verifier: verifier, document-hash: document-hash }))
)

(define-read-only (is-document-registered (document-hash (buff 32)))
  (ok (is-some (map-get? documents { document-hash: document-hash })))
)

(define-read-only (is-document-owner (document-hash (buff 32)) (user principal))
  (ok (is-eq user (get owner (default-to 
    { owner: contract-owner, timestamp: u0, block-height: u0, description: "", verified: false, verification-count: u0 }
    (map-get? documents { document-hash: document-hash })
  ))))
)

;; Public Functions
(define-public (register-document (document-hash (buff 32)) (description (string-ascii 256)))
  (let
    (
      (caller tx-sender)
      (current-count (var-get total-documents))
      (user-count (get count (default-to { count: u0 } (map-get? user-document-count { owner: caller }))))
    )
    (asserts! (is-valid-hash document-hash) err-invalid-hash)
    (asserts! (is-none (map-get? documents { document-hash: document-hash })) err-already-exists)
    
    (map-set documents
      { document-hash: document-hash }
      {
        owner: caller,
        timestamp: burn-block-height,
        block-height: burn-block-height,
        description: description,
        verified: false,
        verification-count: u0
      }
    )
    
    (map-set user-documents
      { owner: caller, index: user-count }
      { document-hash: document-hash }
    )
    
    (map-set user-document-count
      { owner: caller }
      { count: (+ user-count u1) }
    )
    
    (var-set total-documents (+ current-count u1))
    (ok true)
  )
)

(define-public (transfer-ownership (document-hash (buff 32)) (new-owner principal))
  (let
    (
      (caller tx-sender)
      (document-info (unwrap! (map-get? documents { document-hash: document-hash }) err-not-found))
      (current-owner (get owner document-info))
      (transfer-count (get count (default-to { count: u0 } (map-get? ownership-transfer-count { document-hash: document-hash }))))
      (new-user-count (get count (default-to { count: u0 } (map-get? user-document-count { owner: new-owner }))))
    )
    (asserts! (is-eq caller current-owner) err-unauthorized)
    (asserts! (not (is-eq caller new-owner)) err-invalid-transfer)
    
    (map-set documents
      { document-hash: document-hash }
      (merge document-info { owner: new-owner })
    )
    
    (map-set document-ownership-history
      { document-hash: document-hash, index: transfer-count }
      {
        previous-owner: caller,
        new-owner: new-owner,
        transfer-timestamp: burn-block-height,
        transfer-block-height: burn-block-height
      }
    )
    
    (map-set ownership-transfer-count
      { document-hash: document-hash }
      { count: (+ transfer-count u1) }
    )
    
    (map-set user-documents
      { owner: new-owner, index: new-user-count }
      { document-hash: document-hash }
    )
    
    (map-set user-document-count
      { owner: new-owner }
      { count: (+ new-user-count u1) }
    )
    
    (ok true)
  )
)

(define-public (verify-document (document-hash (buff 32)) (verification-note (string-ascii 256)))
  (let
    (
      (caller tx-sender)
      (document-info (unwrap! (map-get? documents { document-hash: document-hash }) err-not-found))
      (current-verification-count (get verification-count document-info))
      (total-verifs (var-get total-verifications))
    )
    (map-set documents
      { document-hash: document-hash }
      (merge document-info 
        { 
          verified: true,
          verification-count: (+ current-verification-count u1)
        }
      )
    )
    
    (map-set verifier-records
      { verifier: caller, document-hash: document-hash }
      {
        verified-at: burn-block-height,
        verified-block: burn-block-height,
        verification-note: verification-note
      }
    )
    
    (var-set total-verifications (+ total-verifs u1))
    (ok true)
  )
)

(define-public (update-document-description (document-hash (buff 32)) (new-description (string-ascii 256)))
  (let
    (
      (caller tx-sender)
      (document-info (unwrap! (map-get? documents { document-hash: document-hash }) err-not-found))
      (current-owner (get owner document-info))
    )
    (asserts! (is-eq caller current-owner) err-unauthorized)
    
    (map-set documents
      { document-hash: document-hash }
      (merge document-info { description: new-description })
    )
    (ok true)
  )
)

;; Admin Functions
(define-public (get-contract-stats)
  (ok {
    total-documents: (var-get total-documents),
    total-verifications: (var-get total-verifications)
  })
)

;; title: document-timestamp-anchor
;; version:
;; summary:
;; description:

;; traits
;;

;; token definitions
;;

;; constants
;;

;; data vars
;;

;; data maps
;;

;; public functions
;;

;; read only functions
;;

;; private functions
;;

