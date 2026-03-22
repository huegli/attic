(ns atari.memory.explore
  "Advanced exploration: extending the protocol-based design.

   Work through these RCFs to see how Approach 2 composes,
   extends, and enables testing patterns that are impossible
   with the flat vector approach.")

(require '[atari.memory.bus :as bus])

;; ---------------------------------------------------------------------------
;; Extension 1: a custom cartridge that satisfies MemoryMapped
;; ---------------------------------------------------------------------------

(defrecord BankSwitchedCart [banks current-bank base-addr]
  ;; A 16KB cartridge with multiple 8KB banks.
  ;; Writing to any address in the cart's range switches the bank.
  bus/MemoryMapped
  (mem-read [_ address]
    (let [bank-data (nth banks current-bank)
          offset    (- address base-addr)]
      (nth bank-data offset 0)))
  (mem-write [this _address value]
    ;; Write selects the bank (modulo number of banks)
    (assoc this :current-bank (mod value (count banks)))))

(defn make-test-cart
  "Create a 2-bank cartridge for demo purposes.
   Bank 0 is filled with $AA, bank 1 with $BB."
  []
  (->BankSwitchedCart [(vec (repeat 0x2000 0xAA))
                       (vec (repeat 0x2000 0xBB))]
                      0
                      0xA000))

;; ---------------------------------------------------------------------------
;; Extension 2: a recording device for capture/replay
;; ---------------------------------------------------------------------------

(defn recording-device
  "Wrap a MemoryMapped device to record all writes.
   Returns a device whose metadata contains an :writes atom."
  [device]
  (let [log (atom [])]
    (with-meta
      (reify bus/MemoryMapped
        (mem-read [_ addr]
          (bus/mem-read device addr))
        (mem-write [_ addr val]
          (swap! log conj {:addr addr :val val})
          (recording-device (bus/mem-write device addr val))))
      {:writes log})))

;; ===========================================================================
;; Rich Comment Forms
;; ===========================================================================

(comment
  ;; ---- Extension 1: Plug in a bank-switched cartridge ----

  ;; Create a bus with our custom cartridge instead of the default BASIC ROM
  (def cart (make-test-cart))
  (def bus (assoc (bus/make-bus) :basic-rom cart))

  ;; Enable the cartridge by clearing PIA PORTB bit 1
  (def bus2 (bus/mem-write bus 0xD301 0xFD))
  (bus/basic-enabled? (:pia bus2))   ;=> true

  ;; Read from bank 0 — filled with $AA
  (bus/mem-read bus2 0xA000)         ;=> 0xAA = 170

  ;; Switch to bank 1 by writing to the cart region
  ;; (The bus routes writes through; our cart interprets them as bank switches)
  (def bus3 (bus/mem-write bus2 0xA000 1))
  (bus/mem-read bus3 0xA000)         ;=> 0xBB = 187

  ;; Switch back to bank 0
  (def bus4 (bus/mem-write bus3 0xA000 0))
  (bus/mem-read bus4 0xA000)         ;=> 0xAA = 170

  ;; We added bank-switching support WITHOUT modifying Bus, POKEY,
  ;; GTIA, or any existing code.  Just a new record + MemoryMapped.


  ;; ---- Extension 2: Record all POKEY writes ----

  (def rec-pokey (recording-device (bus/make-pokey)))
  (def bus-rec (assoc (bus/make-bus) :pokey rec-pokey))

  ;; Do some writes
  (def bus-r2 (-> bus-rec
                  (bus/mem-write 0xD200 0x40)    ; AUDF1
                  (bus/mem-write 0xD201 0xA4)    ; AUDC1
                  (bus/mem-write 0xD200 0x80)))   ; AUDF1 again

  ;; Inspect the write log captured on the original recorder
  @(:writes (meta rec-pokey))
  ;=> [{:addr 53760, :val 64}]
  ;; Note: only the first write was captured on this instance because
  ;; each mem-write returns a NEW recording-device.  This is how
  ;; immutability works — each state has its own write captured.

  ;; For a mutable log across all states, use a shared atom:
  (def shared-log (atom []))
  (def bus-shared
    (assoc (bus/make-bus) :pokey
      (let [pokey (bus/make-pokey)]
        (reify bus/MemoryMapped
          (mem-read [_ addr] (bus/mem-read pokey addr))
          (mem-write [_ addr val]
            (swap! shared-log conj {:addr addr :val val :frame 0})
            (bus/mem-write pokey addr val))))))

  ;; Hmm — but now writes don't propagate to the pokey state.
  ;; This is a real design tension: immutable vs observable.
  ;; Approach 2 makes the tension explicit; Approach 1 hides it.


  ;; ---- Composition: nesting protocols ----

  ;; You can build higher-level abstractions on MemoryMapped.
  ;; For example, a "mirrored region" device:
  (defn mirrored
    "Wrap a device so that `n` consecutive mirrors of `size` bytes
     all map to the same underlying device."
    [device size]
    (reify bus/MemoryMapped
      (mem-read [_ addr]
        (bus/mem-read device (mod addr size)))
      (mem-write [_ addr val]
        (mirrored (bus/mem-write device (mod addr size) val) size))))

  ;; POKEY mirrors every 16 bytes across $D200–$D2FF.
  ;; Our POKEY record already handles this internally, but you could
  ;; also express it structurally:
  (def mirrored-pokey (mirrored (bus/make-pokey) 16))
  (def mp2 (bus/mem-write mirrored-pokey 0x10 0x42))  ; addr 16 → maps to 0
  (bus/mem-read mp2 0x00)   ;=> 66 — same as address 0

  ;; ---- Summary ----
  ;; Approach 2 gives you:
  ;;   - Open extension (new chips without modifying existing code)
  ;;   - Easy testing (reify mocks in one line)
  ;;   - Composable wrappers (logging, recording, mirroring)
  ;;   - Inspectable chip state (each record is a map)
  ;;   - All the immutability/snapshot benefits of Approach 1
  ;;   - At the cost of: slightly more upfront structure

  :rcf)
