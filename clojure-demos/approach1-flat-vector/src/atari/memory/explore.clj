(ns atari.memory.explore
  "Side-by-side exploration: limitations of the flat approach.

   Work through these RCFs to see where Approach 1 starts to hurt.")

(require '[atari.memory.flat :as flat])

(comment
  ;; ---- Limitation 1: No chip isolation ----
  ;; Q: What state is POKEY in right now?
  ;; A: You have to know which shadow keys to look at.
  (def m (-> (flat/make-machine)
             (flat/mem-write flat/AUDF1 100)
             (flat/mem-write flat/AUDC1 0xA8)))

  ;; There's no "pokey" object to inspect — just loose keys
  (select-keys m [:pokey-freq :pokey-ctl])
  ;; For 16 POKEY registers, you'd need 16 shadow keys cluttering
  ;; the top-level machine map.

  ;; ---- Limitation 2: Adding a new chip ----
  ;; Suppose we need to add ANTIC (display list processor).
  ;; We'd have to:
  ;;   1. Add shadow keys to make-machine
  ;;   2. Add cond branches to mem-read
  ;;   3. Add cond branches to mem-write
  ;; All in the same namespace — no separation of concerns.

  ;; ---- Limitation 3: No polymorphism ----
  ;; Can't swap in a mock POKEY for testing:
  ;; (assoc m :pokey mock-pokey)  ← doesn't work, there's no :pokey

  ;; ---- Limitation 4: address decoding is tangled with behaviour ----
  ;; In mem-write, the routing logic (which address goes where) is
  ;; mixed with the chip behaviour (what happens on write).
  ;; In Approach 2, routing is in Bus, behaviour is in each chip record.

  ;; ---- When IS this approach good enough? ----
  ;; - Quick prototyping / proof of concept
  ;; - Very simple systems (e.g. a fantasy console with no hardware I/O)
  ;; - When you're learning and don't want protocol overhead yet

  :rcf)
