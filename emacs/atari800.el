;;; atari800.el --- Emacs integration for Atari 800 XL emulator -*- lexical-binding: t -*-

;; Copyright (C) 2026
;; Author: Your Name
;; Keywords: games, emulation
;; Version: 1.0.0
;; Package-Requires: ((emacs "27.1"))

;;; Commentary:

;; This package provides Emacs integration for the Atari 800 XL emulator.
;; It uses comint-mode to provide an interactive REPL for debugging,
;; BASIC programming, and disk management.

;; Usage:
;;   M-x atari800-run     Start the emulator REPL
;;   M-x atari800-connect Connect to running emulator

;;; Code:

(require 'comint)

;;; Customization

(defgroup atari800 nil
  "Atari 800 XL emulator integration."
  :group 'applications
  :prefix "atari800-")

(defcustom atari800-program "atari800"
  "Path to the Atari 800 XL CLI program."
  :type 'string
  :group 'atari800)

(defcustom atari800-program-args '("--repl")
  "Arguments to pass to the CLI program."
  :type '(repeat string)
  :group 'atari800)

(defcustom atari800-socket-path nil
  "Path to socket for connecting to existing emulator.
If nil, launch a new emulator process."
  :type '(choice (const nil) string)
  :group 'atari800)

;;; Faces

(defface atari800-prompt-face
  '((t :foreground "cyan" :weight bold))
  "Face for REPL prompts."
  :group 'atari800)

(defface atari800-error-face
  '((t :foreground "red"))
  "Face for error messages."
  :group 'atari800)

(defface atari800-address-face
  '((t :foreground "yellow"))
  "Face for memory addresses."
  :group 'atari800)

(defface atari800-keyword-face
  '((t :foreground "green" :weight bold))
  "Face for BASIC keywords."
  :group 'atari800)

;;; Mode definition

(defvar atari800-prompt-regexp "^\\[\\(monitor\\|basic\\|dos\\)\\] [^>]*> "
  "Regexp matching the REPL prompt.")

(defvar atari800-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-r") #'atari800-run-program)
    (define-key map (kbd "C-c C-s") #'atari800-stop)
    (define-key map (kbd "C-c C-m") #'atari800-switch-to-monitor)
    (define-key map (kbd "C-c C-b") #'atari800-switch-to-basic)
    (define-key map (kbd "C-c C-d") #'atari800-switch-to-dos)
    (define-key map (kbd "C-c C-g") #'atari800-go)
    (define-key map (kbd "C-c C-n") #'atari800-step)
    (define-key map (kbd "C-c C-p") #'atari800-pause)
    (define-key map (kbd "C-c C-k") #'atari800-screenshot)
    map)
  "Keymap for `atari800-mode'.")

(defvar atari800-font-lock-keywords
  `(;; Mode prompts
    (,atari800-prompt-regexp 0 'atari800-prompt-face)
    ;; Addresses
    ("\\$[0-9A-Fa-f]\\{2,4\\}" 0 'atari800-address-face)
    ;; Error messages
    ("^Error.*" 0 'atari800-error-face)
    ;; BASIC keywords (subset)
    ("\\<\\(PRINT\\|GOTO\\|GOSUB\\|IF\\|THEN\\|FOR\\|NEXT\\|TO\\|STEP\\|LET\\|DIM\\|REM\\|END\\|RETURN\\|INPUT\\|READ\\|DATA\\|POKE\\|PEEK\\)\\>"
     0 'atari800-keyword-face)
    ;; 6502 mnemonics
    ("\\<\\(LDA\\|LDX\\|LDY\\|STA\\|STX\\|STY\\|ADC\\|SBC\\|AND\\|ORA\\|EOR\\|CMP\\|CPX\\|CPY\\|INC\\|DEC\\|INX\\|INY\\|DEX\\|DEY\\|ASL\\|LSR\\|ROL\\|ROR\\|JMP\\|JSR\\|RTS\\|RTI\\|BRK\\|NOP\\|BCC\\|BCS\\|BEQ\\|BNE\\|BMI\\|BPL\\|BVC\\|BVS\\|CLC\\|CLD\\|CLI\\|CLV\\|SEC\\|SED\\|SEI\\|PHA\\|PHP\\|PLA\\|PLP\\|TAX\\|TAY\\|TSX\\|TXA\\|TXS\\|TYA\\|BIT\\)\\>"
     0 'font-lock-keyword-face))
  "Font lock keywords for `atari800-mode'.")

;;;###autoload
(define-derived-mode atari800-mode comint-mode "Atari800"
  "Major mode for interacting with the Atari 800 XL emulator.

\\{atari800-mode-map}"
  (setq comint-prompt-regexp atari800-prompt-regexp)
  (setq comint-prompt-read-only t)
  (setq comint-use-prompt-regexp t)
  (setq font-lock-defaults '(atari800-font-lock-keywords t))
  (setq-local comint-process-echoes nil)
  
  ;; Handle async events from emulator
  (add-hook 'comint-preoutput-filter-functions
            #'atari800--handle-async-events nil t))

;;; Process management

(defvar atari800--process nil
  "The current Atari 800 process.")

(defun atari800--buffer-name ()
  "Return the buffer name for the Atari 800 REPL."
  "*atari800*")

(defun atari800--get-buffer ()
  "Get or create the Atari 800 buffer."
  (get-buffer-create (atari800--buffer-name)))

;;;###autoload
(defun atari800-run ()
  "Start the Atari 800 XL emulator REPL."
  (interactive)
  (let ((buffer (atari800--get-buffer)))
    (unless (comint-check-proc buffer)
      (with-current-buffer buffer
        (apply #'make-comint-in-buffer
               "atari800"
               buffer
               atari800-program
               nil
               atari800-program-args)
        (atari800-mode)))
    (pop-to-buffer buffer)))

;;;###autoload
(defun atari800-connect (socket-path)
  "Connect to an existing Atari 800 XL emulator at SOCKET-PATH."
  (interactive "fSocket path: ")
  ;; This would use a network process instead of a subprocess
  ;; For now, just use the program with --socket argument
  (let ((buffer (atari800--get-buffer)))
    (unless (comint-check-proc buffer)
      (with-current-buffer buffer
        (make-comint-in-buffer
         "atari800"
         buffer
         atari800-program
         nil
         "--socket" socket-path)
        (atari800-mode)))
    (pop-to-buffer buffer)))

;;; Commands

(defun atari800--send-command (command)
  "Send COMMAND to the Atari 800 process."
  (let ((proc (get-buffer-process (atari800--buffer-name))))
    (when proc
      (comint-send-string proc (concat command "\n")))))

(defun atari800-switch-to-monitor ()
  "Switch to monitor mode."
  (interactive)
  (atari800--send-command ".monitor"))

(defun atari800-switch-to-basic ()
  "Switch to BASIC mode."
  (interactive)
  (atari800--send-command ".basic"))

(defun atari800-switch-to-dos ()
  "Switch to DOS mode."
  (interactive)
  (atari800--send-command ".dos"))

(defun atari800-run-program ()
  "Run the current BASIC program."
  (interactive)
  (atari800--send-command "run"))

(defun atari800-stop ()
  "Stop/break the running program."
  (interactive)
  (atari800--send-command "stop"))

(defun atari800-go ()
  "Resume emulator execution (monitor mode)."
  (interactive)
  (atari800--send-command "g"))

(defun atari800-step (&optional count)
  "Step COUNT instructions in monitor mode."
  (interactive "p")
  (atari800--send-command (format "s %d" (or count 1))))

(defun atari800-pause ()
  "Pause emulator execution."
  (interactive)
  (atari800--send-command "pause"))

(defun atari800-screenshot (&optional path)
  "Take a screenshot, optionally saving to PATH."
  (interactive "FSave screenshot to: ")
  (if path
      (atari800--send-command (format ".screenshot %s" path))
    (atari800--send-command ".screenshot")))

(defun atari800-disassemble (address &optional lines)
  "Disassemble LINES instructions starting at ADDRESS."
  (interactive "sAddress: \np")
  (atari800--send-command (format "d %s %d" address (or lines 16))))

(defun atari800-set-breakpoint (address)
  "Set a breakpoint at ADDRESS."
  (interactive "sAddress: ")
  (atari800--send-command (format "bp %s" address)))

(defun atari800-clear-breakpoint (address)
  "Clear breakpoint at ADDRESS."
  (interactive "sAddress: ")
  (atari800--send-command (format "bc %s" address)))

(defun atari800-memory-dump (address &optional length)
  "Dump LENGTH bytes of memory starting at ADDRESS."
  (interactive "sAddress: \np")
  (atari800--send-command (format "m %s %d" address (or length 64))))

(defun atari800-registers ()
  "Display CPU registers."
  (interactive)
  (atari800--send-command "r"))

;;; BASIC integration

(defun atari800-send-region (start end)
  "Send region from START to END as BASIC program lines."
  (interactive "r")
  (let ((lines (split-string (buffer-substring-no-properties start end) "\n" t)))
    (dolist (line lines)
      (when (string-match "^[0-9]+" line)
        (atari800--send-command line)
        (sit-for 0.1)))))  ; Small delay between lines

(defun atari800-send-buffer ()
  "Send entire buffer as BASIC program."
  (interactive)
  (atari800-send-region (point-min) (point-max)))

;;; Async event handling

(defun atari800--handle-async-events (output)
  "Handle async events in OUTPUT from the emulator."
  (when (string-match "^EVENT:breakpoint \\(\\$[0-9A-Fa-f]+\\)" output)
    (let ((address (match-string 1 output)))
      (message "Breakpoint hit at %s" address)))
  output)

;;; BASIC mode for editing .BAS files

(defvar atari-basic-mode-syntax-table
  (let ((table (make-syntax-table)))
    (modify-syntax-entry ?\" "\"" table)
    (modify-syntax-entry ?\' "<" table)
    (modify-syntax-entry ?\n ">" table)
    table)
  "Syntax table for `atari-basic-mode'.")

(defvar atari-basic-font-lock-keywords
  '(;; Line numbers
    ("^[0-9]+" . font-lock-constant-face)
    ;; Keywords
    ("\\<\\(PRINT\\|GOTO\\|GOSUB\\|IF\\|THEN\\|FOR\\|NEXT\\|TO\\|STEP\\|LET\\|DIM\\|REM\\|END\\|RETURN\\|INPUT\\|READ\\|DATA\\|POKE\\|PEEK\\|AND\\|OR\\|NOT\\|OPEN\\|CLOSE\\|GET\\|PUT\\|GRAPHICS\\|PLOT\\|DRAWTO\\|SETCOLOR\\|COLOR\\|SOUND\\|POSITION\\|LOCATE\\|XIO\\|USR\\|ADR\\|FRE\\|CHR\\$\\|STR\\$\\|VAL\\|LEN\\|ASC\\|ATN\\|COS\\|SIN\\|SQR\\|INT\\|RND\\|ABS\\|SGN\\|LOG\\|EXP\\)\\>"
     . font-lock-keyword-face)
    ;; Strings
    ("\"[^\"]*\"" . font-lock-string-face)
    ;; REM comments
    ("\\<REM\\>.*$" . font-lock-comment-face))
  "Font lock keywords for `atari-basic-mode'.")

;;;###autoload
(define-derived-mode atari-basic-mode prog-mode "AtariBASIC"
  "Major mode for editing Atari BASIC programs."
  :syntax-table atari-basic-mode-syntax-table
  (setq font-lock-defaults '(atari-basic-font-lock-keywords))
  (setq-local comment-start "REM ")
  (setq-local comment-end ""))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.bas\\'" . atari-basic-mode))

;;; Menu

(easy-menu-define atari800-menu atari800-mode-map
  "Menu for Atari 800 mode."
  '("Atari800"
    ["Switch to Monitor" atari800-switch-to-monitor]
    ["Switch to BASIC" atari800-switch-to-basic]
    ["Switch to DOS" atari800-switch-to-dos]
    "---"
    ["Run Program" atari800-run-program]
    ["Stop" atari800-stop]
    ["Go (Resume)" atari800-go]
    ["Step" atari800-step]
    ["Pause" atari800-pause]
    "---"
    ["Show Registers" atari800-registers]
    ["Disassemble..." atari800-disassemble]
    ["Memory Dump..." atari800-memory-dump]
    "---"
    ["Set Breakpoint..." atari800-set-breakpoint]
    ["Clear Breakpoint..." atari800-clear-breakpoint]
    "---"
    ["Screenshot..." atari800-screenshot]))

(provide 'atari800)

;;; atari800.el ends here
