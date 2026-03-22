(ns atari.memory.flat
  "Approach 1: Flat Vector Memory

   The entire 64KB address space is a single persistent vector.
   Hardware side-effects (POKEY sound, GTIA graphics) are handled
   by wrapping reads/writes in a big `cond` dispatcher.

   This is the simplest thing that could possibly work — and it
   does work — but it tangles address decoding, chip behaviour,
   and plain RAM into one place.")

;; ---------------------------------------------------------------------------
;; Memory representation
;; ---------------------------------------------------------------------------

(def ^:const MEM-SIZE 65536)

(defn make-memory
  "Create a fresh 64KB memory image — all zeros."
  []
  (vec (repeat MEM-SIZE 0)))

;; The full machine state: memory + a few I/O shadow registers so we
;; can show that writes to hardware addresses have observable effects.
(defn make-machine
  "Return an initial machine state map.
   :mem        — 64KB flat vector
   :pokey-freq — shadow of AUDF1 (audio frequency channel 1)
   :pokey-ctl  — shadow of AUDC1 (audio control channel 1)
   :gtia-colbk — shadow of COLBK (background colour register)"
  []
  {:mem        (make-memory)
   :pokey-freq 0
   :pokey-ctl  0
   :gtia-colbk 0})

;; ---------------------------------------------------------------------------
;; Address constants (Atari 800 XL hardware registers)
;; ---------------------------------------------------------------------------

;; POKEY: $D200–$D2FF  (sound, keyboard, serial I/O, random number)
(def ^:const AUDF1  0xD200)  ; audio frequency channel 1
(def ^:const AUDC1  0xD201)  ; audio control   channel 1
(def ^:const RANDOM 0xD20A)  ; random number   (read-only)

;; GTIA: $D000–$D0FF  (graphics, colour, collision)
(def ^:const COLBK  0xD01A)  ; playfield background colour

;; ---------------------------------------------------------------------------
;; Read / Write — the big dispatch
;; ---------------------------------------------------------------------------

(defn mem-read
  "Read one byte from `address`.
   Hardware addresses return synthetic values (e.g. RANDOM);
   everything else comes straight from the vector."
  [{:keys [mem pokey-freq pokey-ctl gtia-colbk]} address]
  (cond
    ;; POKEY region
    (= address RANDOM)  (rand-int 256)           ; POKEY random register
    (= address AUDF1)   pokey-freq                ; read back last written freq
    (= address AUDC1)   pokey-ctl                 ; read back last written ctl

    ;; GTIA region
    (= address COLBK)   gtia-colbk                ; read back last written colour

    ;; Everything else — plain RAM / ROM
    :else                (nth mem address)))

(defn mem-write
  "Write one byte `value` to `address`.
   Returns a NEW machine state (nothing is mutated).
   Hardware addresses update their shadow registers;
   ROM region ($C000–$FFFF) silently ignores writes."
  [machine address value]
  (let [value (bit-and value 0xFF)]
    (cond
      ;; POKEY writes
      (= address AUDF1)  (assoc machine :pokey-freq value)
      (= address AUDC1)  (assoc machine :pokey-ctl  value)
      (= address RANDOM) machine                  ; write to RANDOM is a no-op

      ;; GTIA writes
      (= address COLBK)  (assoc machine :gtia-colbk value)

      ;; ROM region — ignore writes
      (<= 0xC000 address 0xFFFF) machine

      ;; Plain RAM
      :else (update machine :mem assoc address value))))

;; ---------------------------------------------------------------------------
;; Convenience: multi-byte operations
;; ---------------------------------------------------------------------------

(defn mem-read-word
  "Read a little-endian 16-bit word (low byte first, as the 6502 expects)."
  [machine address]
  (+ (mem-read machine address)
     (* 256 (mem-read machine (inc address)))))

(defn mem-write-bytes
  "Write a sequence of bytes starting at `address`."
  [machine address bytes]
  (reduce-kv
    (fn [m idx b] (mem-write m (+ address idx) b))
    machine
    (vec bytes)))

;; ---------------------------------------------------------------------------
;; Demo: a tiny 6502 program loader
;; ---------------------------------------------------------------------------

(defn load-program
  "Load a sequence of 6502 opcodes into memory at `org` (origin address).
   Returns updated machine state."
  [machine org opcodes]
  (mem-write-bytes machine org opcodes))

;; ===========================================================================
;; Rich Comment Forms — evaluate these one by one in Calva (Ctrl+Enter)
;; ===========================================================================

(comment
  ;; ---- Getting started ----
  ;; In Calva: Ctrl+Shift+P → "Calva: Start a Project REPL and Connect"
  ;; Choose "Approach 1 — Flat Vector", then the deps.edn alias "dev".
  ;; Once connected, place cursor after each form and press Ctrl+Enter.

  ;; 1. Create a fresh machine
  (def m (make-machine))

  ;; 2. Inspect it — you'll see :mem is a huge vector of zeros
  (count (:mem m))          ;=> 65536
  (nth (:mem m) 0)          ;=> 0
  (:pokey-freq m)           ;=> 0

  ;; 3. Write to plain RAM at address $0600 (page 6, a common staging area)
  (def m2 (mem-write m 0x0600 42))
  (mem-read m2 0x0600)      ;=> 42
  (mem-read m  0x0600)      ;=> 0   — original is unchanged (immutable!)

  ;; 4. Write to a hardware register — POKEY frequency
  (def m3 (mem-write m2 AUDF1 0xAB))
  (:pokey-freq m3)          ;=> 0xAB = 171
  (mem-read m3 AUDF1)       ;=> 171

  ;; 5. Read the RANDOM register — different value each time
  (mem-read m3 RANDOM)      ;=> some random number 0–255
  (mem-read m3 RANDOM)      ;=> probably different!

  ;; 6. Write to ROM region — silently ignored
  (def m4 (mem-write m3 0xC000 0xFF))
  (mem-read m4 0xC000)      ;=> 0   — write was ignored

  ;; 7. GTIA background colour
  (def m5 (mem-write m4 COLBK 0x94))   ; $94 = green on NTSC Atari
  (:gtia-colbk m5)          ;=> 0x94 = 148

  ;; 8. Load a tiny program: LDA #$42, STA $0600, BRK
  ;;    Machine code: A9 42 8D 00 06 00
  (def m6 (load-program m5 0x0600 [0xA9 0x42 0x8D 0x00 0x06 0x00]))
  (map #(mem-read m6 %) (range 0x0600 0x0606))
  ;=> (169 66 141 0 6 0)  i.e. ($A9 $42 $8D $00 $06 $00)

  ;; 9. Read a 16-bit word (little-endian) — useful for vectors
  (def m7 (-> m (mem-write 0x00 0x00) (mem-write 0x01 0x06)))
  (mem-read-word m7 0x00)   ;=> 0x0600 = 1536

  ;; ---- THE PROBLEM with this approach ----
  ;;
  ;; Look at mem-write and mem-read.  Every new hardware chip means
  ;; another branch in the cond.  A real Atari has ANTIC, GTIA, POKEY,
  ;; PIA, plus bank-switching logic.  The cond grows to 50+ branches
  ;; and every chip's behaviour lives in one function.
  ;;
  ;; Also: there's no polymorphism.  You can't swap in a "mock POKEY"
  ;; for testing, or a "logging POKEY" for debugging — you'd have to
  ;; add flags and more cond branches.
  ;;
  ;; Compare with Approach 2 (the protocol-based design).

  ;; 10. Snapshot / time-travel — one real advantage of the flat approach
  ;;     The entire state is just a map, so you can keep history trivially.
  (def history (atom []))
  (swap! history conj m)
  (swap! history conj m3)
  (swap! history conj m5)
  (count @history)           ;=> 3
  (:pokey-freq (nth @history 1))  ;=> 171  (m3's state)
  ;; This works in Approach 2 as well, since records are also immutable maps.

  :rcf)
