(ns atari.memory.bus
  "Approach 2: Protocol-Based Memory Bus

   Each chip (RAM, POKEY, GTIA, PIA) is its own record that satisfies
   the MemoryMapped protocol.  A Bus record routes reads/writes to
   the correct chip based on the address.

   This is the idiomatic Clojure approach: open protocols, small
   composable records, and no god-object dispatch.")

;; ---------------------------------------------------------------------------
;; The core abstraction — anything that can be read/written by address
;; ---------------------------------------------------------------------------

(defprotocol MemoryMapped
  "A device on the Atari's address bus.
   Every chip that responds to CPU reads/writes implements this."
  (mem-read  [this address]       "Read one byte from `address`.")
  (mem-write [this address value] "Write one byte; returns a NEW device (immutable)."))

;; ---------------------------------------------------------------------------
;; RAM — 64KB of general-purpose memory
;; ---------------------------------------------------------------------------

(defrecord RAM [data]
  ;; `data` is a persistent vector of 65536 bytes.
  MemoryMapped
  (mem-read [_ address]
    (nth data address))
  (mem-write [this address value]
    ;; Returns a new RAM with one byte changed — O(log32 N) via Clojure's
    ;; persistent vector (a 32-way trie under the hood).
    (assoc this :data (assoc data address (bit-and value 0xFF)))))

(defn make-ram
  "Create a zeroed 64KB RAM."
  []
  (->RAM (vec (repeat 65536 0))))

;; ---------------------------------------------------------------------------
;; POKEY — sound, keyboard scan, serial I/O, random number generator
;; Mapped to $D200–$D2FF on the Atari 800 XL.
;; ---------------------------------------------------------------------------

(defrecord POKEY [audf1 audc1 audf2 audc2]
  ;; Four of the eight audio registers for demonstration.
  ;; A full implementation would have all 16+ registers.
  MemoryMapped
  (mem-read [this address]
    ;; POKEY mirrors every 16 bytes in $D200–$D2FF, so mask to low nibble.
    (case (bit-and address 0x0F)
      0x00 audf1
      0x01 audc1
      0x02 audf2
      0x03 audc2
      0x0A (rand-int 256)          ; RANDOM register — non-deterministic
      0))                          ; unimplemented registers read as 0

  (mem-write [this address value]
    (let [v (bit-and value 0xFF)]
      (case (bit-and address 0x0F)
        0x00 (assoc this :audf1 v)
        0x01 (assoc this :audc1 v)
        0x02 (assoc this :audf2 v)
        0x03 (assoc this :audc2 v)
        ;; Writes to read-only or unimplemented registers are silently ignored.
        this))))

(defn make-pokey [] (->POKEY 0 0 0 0))

;; ---------------------------------------------------------------------------
;; GTIA — graphics, player/missile, colour registers
;; Mapped to $D000–$D0FF.
;; ---------------------------------------------------------------------------

(defrecord GTIA [colpm0 colpm1 colpf0 colpf1 colpf2 colpf3 colbk]
  ;; Colour registers only; a full GTIA has collision detection, priority, etc.
  MemoryMapped
  (mem-read [this address]
    (case (bit-and address 0x1F)
      0x12 colpm0
      0x13 colpm1
      0x14 colpf0
      0x15 colpf1
      0x16 colpf2
      0x17 colpf3
      0x1A colbk
      0))

  (mem-write [this address value]
    (let [v (bit-and value 0xFF)]
      (case (bit-and address 0x1F)
        0x12 (assoc this :colpm0 v)
        0x13 (assoc this :colpm1 v)
        0x14 (assoc this :colpf0 v)
        0x15 (assoc this :colpf1 v)
        0x16 (assoc this :colpf2 v)
        0x17 (assoc this :colpf3 v)
        0x1A (assoc this :colbk  v)
        this))))

(defn make-gtia [] (->GTIA 0 0 0 0 0 0 0))

;; ---------------------------------------------------------------------------
;; PIA (6520) — parallel I/O, bank switching
;; Mapped to $D300–$D3FF.
;; ---------------------------------------------------------------------------

(defrecord PIA [porta portb]
  ;; PORTA: joystick ports, PORTB: memory bank control.
  ;; Bit 1 of PORTB controls BASIC ROM enable on the 800 XL.
  MemoryMapped
  (mem-read [this address]
    (case (bit-and address 0x03)
      0x00 porta
      0x01 portb
      0))

  (mem-write [this address value]
    (let [v (bit-and value 0xFF)]
      (case (bit-and address 0x03)
        0x00 (assoc this :porta v)
        0x01 (assoc this :portb v)
        this))))

(defn make-pia []
  ;; PORTB defaults to $FF on the XL — all banks enabled.
  (->PIA 0 0xFF))

;; ---------------------------------------------------------------------------
;; ROM — read-only memory (BASIC ROM, OS ROM, cartridge)
;; ---------------------------------------------------------------------------

(defrecord ROM [data base-addr]
  ;; `data` is a vector of bytes; `base-addr` is the start of the ROM window.
  MemoryMapped
  (mem-read [_ address]
    (nth data (- address base-addr) 0))
  (mem-write [this _address _value]
    ;; Writes to ROM are silently ignored — just like real hardware.
    this))

(defn make-rom
  "Create a ROM from a byte vector mapped at `base-addr`."
  [base-addr bytes]
  (->ROM (vec bytes) base-addr))

;; ---------------------------------------------------------------------------
;; The Bus — routes addresses to the correct chip
;; ---------------------------------------------------------------------------

(defn basic-enabled?
  "Check PIA PORTB bit 1 — when clear, BASIC ROM is mapped at $A000–$BFFF."
  [pia]
  (zero? (bit-and (:portb pia) 0x02)))

(defrecord Bus [ram pokey gtia pia basic-rom os-rom]
  MemoryMapped
  (mem-read [this address]
    (cond
      ;; GTIA: $D000–$D0FF
      (<= 0xD000 address 0xD0FF) (mem-read gtia address)

      ;; POKEY: $D200–$D2FF
      (<= 0xD200 address 0xD2FF) (mem-read pokey address)

      ;; PIA: $D300–$D3FF
      (<= 0xD300 address 0xD3FF) (mem-read pia address)

      ;; BASIC ROM: $A000–$BFFF (bank-switched via PIA PORTB)
      (and (<= 0xA000 address 0xBFFF)
           (basic-enabled? pia))
      (mem-read basic-rom address)

      ;; OS ROM: $C000–$FFFF (simplified — always mapped)
      (<= 0xC000 address 0xFFFF)
      (mem-read os-rom address)

      ;; Everything else is RAM
      :else (mem-read ram address)))

  (mem-write [this address value]
    (cond
      (<= 0xD000 address 0xD0FF) (update this :gtia  mem-write address value)
      (<= 0xD200 address 0xD2FF) (update this :pokey mem-write address value)
      (<= 0xD300 address 0xD3FF) (update this :pia   mem-write address value)

      ;; Writes to ROM regions are silently dropped
      (<= 0xC000 address 0xFFFF) this
      (and (<= 0xA000 address 0xBFFF) (basic-enabled? pia)) this

      ;; RAM
      :else (update this :ram mem-write address value))))

(defn make-bus
  "Create a complete Atari memory bus with all chips.
   Optionally pass :basic-rom and :os-rom byte vectors."
  [& {:keys [basic-rom-bytes os-rom-bytes]}]
  (->Bus (make-ram)
         (make-pokey)
         (make-gtia)
         (make-pia)
         (make-rom 0xA000 (or basic-rom-bytes (vec (repeat 0x2000 0xFF))))
         (make-rom 0xC000 (or os-rom-bytes   (vec (repeat 0x4000 0xFF))))))

;; ---------------------------------------------------------------------------
;; Convenience helpers (same API as Approach 1 for easy comparison)
;; ---------------------------------------------------------------------------

(defn mem-read-word
  "Read a little-endian 16-bit word."
  [bus address]
  (+ (mem-read bus address)
     (* 256 (mem-read bus (inc address)))))

(defn mem-write-bytes
  "Write a sequence of bytes starting at `address`."
  [bus address bytes]
  (reduce-kv
    (fn [b idx byte] (mem-write b (+ address idx) byte))
    bus
    (vec bytes)))

(defn load-program
  "Load 6502 opcodes into the bus at `org`."
  [bus org opcodes]
  (mem-write-bytes bus org opcodes))

;; ===========================================================================
;; Rich Comment Forms — evaluate these one by one in Calva (Ctrl+Enter)
;; ===========================================================================

(comment
  ;; ---- Getting started ----
  ;; In Calva: Ctrl+Shift+P → "Calva: Start a Project REPL and Connect"
  ;; Choose "Approach 2 — Protocol", then the deps.edn alias "dev".

  ;; 1. Create a full machine with all chips
  (def bus (make-bus))

  ;; 2. It's a record (which is also a map) — inspect its keys
  (keys bus)    ;=> (:ram :pokey :gtia :pia :basic-rom :os-rom)
  (type bus)    ;=> atari.memory.bus.Bus

  ;; 3. Each chip is its own record
  (type (:pokey bus))   ;=> atari.memory.bus.POKEY
  (:audf1 (:pokey bus)) ;=> 0

  ;; 4. Write to plain RAM
  (def bus2 (mem-write bus 0x0600 42))
  (mem-read bus2 0x0600)   ;=> 42
  (mem-read bus  0x0600)   ;=> 0  — immutable!

  ;; 5. Write to POKEY — the bus routes it to the POKEY record
  (def bus3 (mem-write bus2 0xD200 0xAB))  ; AUDF1
  (:audf1 (:pokey bus3))   ;=> 171  — the POKEY record was updated
  (mem-read bus3 0xD200)   ;=> 171  — reading goes through the same routing

  ;; 6. The RAM was NOT touched by the POKEY write
  (nth (:data (:ram bus3)) 0xD200)  ;=> 0  — RAM at that address is still 0

  ;; 7. POKEY RANDOM register
  (mem-read bus3 0xD20A)   ;=> random 0–255
  (mem-read bus3 0xD20A)   ;=> different!

  ;; 8. GTIA background colour
  (def bus4 (mem-write bus3 0xD01A 0x94))  ; COLBK = green
  (:colbk (:gtia bus4))    ;=> 148

  ;; 9. ROM is read-only — writes silently ignored
  (def bus5 (mem-write bus4 0xC000 0xFF))
  (mem-read bus5 0xC000)   ;=> 0xFF  — that's the ROM fill byte, not our write!
  (= (:os-rom bus4) (:os-rom bus5))  ;=> true — ROM record unchanged

  ;; 10. Bank switching — PIA PORTB controls BASIC ROM visibility
  ;;     Default PORTB = $FF → bit 1 is set → BASIC is DISABLED
  (basic-enabled? (:pia bus))  ;=> false

  ;;     Clear bit 1 to enable BASIC ROM at $A000–$BFFF
  (def bus-basic (mem-write bus 0xD301 0xFD))  ; PORTB ← $FD (bit 1 clear)
  (basic-enabled? (:pia bus-basic))  ;=> true
  (mem-read bus-basic 0xA000)  ;=> 0xFF — BASIC ROM content (fill byte)

  ;;     With BASIC disabled, $A000 reads from RAM instead
  (def bus-no-basic (mem-write bus 0xD301 0xFF))
  (basic-enabled? (:pia bus-no-basic))  ;=> false
  (mem-read bus-no-basic 0xA000)  ;=> 0 — that's RAM, not ROM

  ;; 11. Load a program — same API as Approach 1
  (def bus6 (load-program bus5 0x0600 [0xA9 0x42 0x8D 0x00 0x06 0x00]))
  (map #(mem-read bus6 %) (range 0x0600 0x0606))
  ;=> (169 66 141 0 6 0)

  ;; ---- WHY this approach is better ----

  ;; 12. Polymorphism: each chip only knows about itself
  ;;     POKEY doesn't know about GTIA, GTIA doesn't know about RAM.
  ;;     The Bus only knows address ranges, not chip internals.

  ;; 13. You can inspect any chip independently
  (:pokey bus3)  ;=> #atari.memory.bus.POKEY{:audf1 171, :audc1 0, ...}

  ;; 14. You can create a mock chip for testing with `reify`
  (def mock-pokey
    (reify MemoryMapped
      (mem-read  [_ _addr]        0xBE)   ; always returns $BE
      (mem-write [this _addr _val] this))) ; writes are no-ops

  (mem-read mock-pokey 0xD200)   ;=> 0xBE = 190

  ;; 15. Swap mock into the bus — no code changes needed!
  (def test-bus (assoc bus :pokey mock-pokey))
  (mem-read test-bus 0xD200)     ;=> 190   — uses mock
  (mem-read test-bus 0x0600)     ;=> 0     — RAM still works

  ;; 16. A "logging" wrapper — decorate any chip without modifying it
  (defn logging-device
    "Wrap a MemoryMapped device to print all reads and writes."
    [device name]
    (reify MemoryMapped
      (mem-read [_ addr]
        (let [v (mem-read device addr)]
          (println (format "[%s] READ  $%04X → $%02X" name addr v))
          v))
      (mem-write [_ addr val]
        (println (format "[%s] WRITE $%04X ← $%02X" name addr val))
        (logging-device (mem-write device addr val) name))))

  (def debug-bus (update bus :pokey logging-device "POKEY"))
  (mem-read  debug-bus 0xD200)    ; prints: [POKEY] READ  $D200 → $00
  (mem-write debug-bus 0xD200 99) ; prints: [POKEY] WRITE $D200 ← $63

  ;; Try doing any of this in Approach 1 without a massive refactor!

  ;; 17. Time-travel still works — records are immutable maps
  (def history (atom []))
  (swap! history conj bus)
  (swap! history conj bus3)
  (swap! history conj bus4)
  (:audf1 (:pokey (nth @history 1)))  ;=> 171

  ;; 18. Diffing two states — which chips changed?
  (defn diff-chips [bus-a bus-b]
    (into {}
      (for [k (keys bus-a)
            :when (not= (get bus-a k) (get bus-b k))]
        [k {:before (get bus-a k) :after (get bus-b k)}])))

  (diff-chips bus bus3)
  ;; Shows that :ram and :pokey changed, everything else identical

  :rcf)
