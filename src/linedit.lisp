;;;; linedit.lisp - Pure Common Lisp line editor with history
;;;;
;;;; A terminal line editor supporting:
;;;;   - Command history navigation (Up/Down arrows)
;;;;   - Cursor movement (Left/Right arrows, Home/End)
;;;;   - Line editing (Backspace, Delete, Ctrl+K, Ctrl+U)
;;;;   - Persistent history file support
;;;;
;;;; No external libraries required - uses POSIX terminal control via stty.

(defpackage #:coalton-impl/linedit
  (:use #:cl)
  (:export
   #:linedit                          ; FUNCTION - read a line with editing
   #:make-history                     ; FUNCTION - create history object
   #:history-add                      ; FUNCTION - add line to history
   #:history-load                     ; FUNCTION - load history from file
   #:history-save                     ; FUNCTION - save history to file
   #:*default-history-size*           ; VARIABLE
   ))

(in-package #:coalton-impl/linedit)

;;;
;;; Configuration
;;;

(defvar *default-history-size* 500
  "Default maximum number of history entries.")

;;;
;;; History Management
;;;

(defstruct history
  "Command history with navigation support."
  (entries (make-array 0 :adjustable t :fill-pointer 0) :type vector)
  (max-size *default-history-size* :type fixnum)
  (position 0 :type fixnum)           ; Current navigation position
  (saved-line "" :type string))       ; Line saved when navigating

(defun history-add (history line)
  "Add LINE to HISTORY if non-empty and different from last entry."
  (when (and (plusp (length line))
             (or (zerop (length (history-entries history)))
                 (string/= line (aref (history-entries history)
                                      (1- (length (history-entries history)))))))
    ;; Remove oldest if at capacity
    (when (>= (length (history-entries history))
              (history-max-size history))
      (loop for i from 0 below (1- (length (history-entries history)))
            do (setf (aref (history-entries history) i)
                     (aref (history-entries history) (1+ i))))
      (decf (fill-pointer (history-entries history))))
    ;; Add new entry
    (vector-push-extend line (history-entries history)))
  ;; Reset navigation position
  (setf (history-position history) (length (history-entries history)))
  (setf (history-saved-line history) ""))

(defun history-previous (history current-line)
  "Navigate to previous history entry, returning it or NIL if at beginning."
  (when (plusp (history-position history))
    ;; Save current line if at the end
    (when (= (history-position history) (length (history-entries history)))
      (setf (history-saved-line history) current-line))
    (decf (history-position history))
    (aref (history-entries history) (history-position history))))

(defun history-next (history)
  "Navigate to next history entry, returning it or saved line if at end."
  (when (< (history-position history) (length (history-entries history)))
    (incf (history-position history))
    (if (= (history-position history) (length (history-entries history)))
        (history-saved-line history)
        (aref (history-entries history) (history-position history)))))

(defun history-reset-position (history)
  "Reset history navigation to the end."
  (setf (history-position history) (length (history-entries history)))
  (setf (history-saved-line history) ""))

(defun history-load (history pathname)
  "Load history from PATHNAME."
  (when (probe-file pathname)
    (with-open-file (stream pathname :direction :input
                                     :if-does-not-exist nil)
      (when stream
        (loop for line = (read-line stream nil nil)
              while line
              do (history-add history line))))))

(defun history-save (history pathname)
  "Save history to PATHNAME."
  (with-open-file (stream pathname :direction :output
                                   :if-exists :supersede
                                   :if-does-not-exist :create)
    (loop for entry across (history-entries history)
          do (write-line entry stream))))

;;;
;;; Terminal Control
;;;

(defvar *original-termios* nil
  "Saved terminal settings for restoration.")

(defun run-stty (args)
  "Run stty with ARGS, returning (values output exit-code)."
  (ignore-errors
    #+sbcl
    (let* ((process (sb-ext:run-program "/bin/stty" args
                                        :search nil
                                        :input t      ; inherit stdin
                                        :output :stream
                                        :error nil
                                        :wait t))
           (output (when (sb-ext:process-output process)
                     (let ((s (make-string-output-stream)))
                       (loop for line = (read-line (sb-ext:process-output process) nil nil)
                             while line do (write-line line s))
                       (get-output-stream-string s))))
           (exit-code (sb-ext:process-exit-code process)))
      (values (string-trim '(#\Newline #\Return #\Space) (or output ""))
              exit-code))
    #+ccl
    (let* ((process (ccl:run-program "/bin/stty" args
                                     :input t
                                     :output :stream
                                     :error nil
                                     :wait t))
           (output (when (ccl:external-process-output-stream process)
                     (let ((s (make-string-output-stream)))
                       (loop for line = (read-line (ccl:external-process-output-stream process) nil nil)
                             while line do (write-line line s))
                       (get-output-stream-string s))))
           (exit-code (nth-value 1 (ccl:external-process-status process))))
      (values (string-trim '(#\Newline #\Return #\Space) (or output ""))
              exit-code))
    #-(or sbcl ccl)
    (multiple-value-bind (output error-output exit-code)
        (uiop:run-program (cons "stty" args)
                          :output :string
                          :error-output nil
                          :ignore-error-status t)
      (declare (ignore error-output))
      (values (string-trim '(#\Newline #\Return #\Space) (or output ""))
              exit-code))))

(defun terminal-raw-mode ()
  "Put terminal in raw mode for character-by-character input.
   Returns T on success, NIL on failure."
  ;; Save current settings
  (multiple-value-bind (output exit-code)
      (run-stty '("-g"))
    (unless (eql exit-code 0)
      (return-from terminal-raw-mode nil))
    (setf *original-termios* output))

  ;; Check if we got valid settings
  (when (or (null *original-termios*)
            (zerop (length *original-termios*)))
    (return-from terminal-raw-mode nil))

  ;; Set raw mode: disable canonical mode, echo, and signals
  (multiple-value-bind (output exit-code)
      (run-stty '("raw" "-echo" "-isig" "-icanon"))
    (declare (ignore output))
    (eql exit-code 0)))

(defun terminal-restore ()
  "Restore terminal to original settings."
  (when (and *original-termios*
             (plusp (length *original-termios*)))
    (run-stty (list *original-termios*))))


;;;
;;; ANSI Escape Sequence Parsing
;;;

(defconstant +escape+ (code-char 27))
(defconstant +backspace+ (code-char 127))
(defconstant +ctrl-a+ (code-char 1))
(defconstant +ctrl-c+ (code-char 3))
(defconstant +ctrl-d+ (code-char 4))
(defconstant +ctrl-e+ (code-char 5))
(defconstant +ctrl-k+ (code-char 11))
(defconstant +ctrl-l+ (code-char 12))
(defconstant +ctrl-u+ (code-char 21))
(defconstant +ctrl-w+ (code-char 23))
(defconstant +enter+ (code-char 13))
(defconstant +newline+ (code-char 10))

(defun parse-escape-sequence (stream)
  "Parse an escape sequence and return a keyword representing the key.
   Returns :UNKNOWN for unrecognized sequences."
  (let ((char1 (read-char stream nil nil)))
    (unless char1
      (return-from parse-escape-sequence :escape))

    (case char1
      ;; CSI sequences: ESC [
      (#\[
       (let ((char2 (read-char stream nil nil)))
         (unless char2
           (return-from parse-escape-sequence :unknown))
         (case char2
           (#\A :up)
           (#\B :down)
           (#\C :right)
           (#\D :left)
           (#\H :home)
           (#\F :end)
           ;; Extended sequences like ESC [ 1 ~ (Home) or ESC [ 3 ~ (Delete)
           ((#\1 #\2 #\3 #\4 #\5 #\6 #\7 #\8)
            (let ((char3 (read-char stream nil nil)))
              (case char3
                (#\~ (case char2
                       (#\1 :home)
                       (#\3 :delete)
                       (#\4 :end)
                       (#\5 :page-up)
                       (#\6 :page-down)
                       (t :unknown)))
                (t :unknown))))
           (t :unknown))))
      ;; SS3 sequences: ESC O (alternate arrow keys on some terminals)
      (#\O
       (let ((char2 (read-char stream nil nil)))
         (case char2
           (#\A :up)
           (#\B :down)
           (#\C :right)
           (#\D :left)
           (#\H :home)
           (#\F :end)
           (t :unknown))))
      (t :unknown))))

(defun read-key (stream)
  "Read a key from STREAM, handling escape sequences.
   Returns either a character or a keyword for special keys.
   Returns :EOF on end of input, :INTERRUPT on Ctrl+C."
  (let ((char (read-char stream nil :eof)))
    (cond
      ((eq char :eof) :eof)
      ((char= char +escape+)
       ;; Start of escape sequence - read next char (blocking)
       ;; Escape sequences come in quick succession, so blocking is fine
       (parse-escape-sequence stream))
      ((char= char +ctrl-c+) :interrupt)
      ((char= char +ctrl-d+) :eof)
      ((char= char +ctrl-a+) :home)
      ((char= char +ctrl-e+) :end)
      ((char= char +ctrl-k+) :kill-to-end)
      ((char= char +ctrl-u+) :kill-to-start)
      ((char= char +ctrl-w+) :kill-word)
      ((char= char +ctrl-l+) :clear-screen)
      ((or (char= char +backspace+)
           (char= char (code-char 8)))
       :backspace)
      ((or (char= char +enter+)
           (char= char +newline+))
       :enter)
      (t char))))

;;;
;;; Line Display
;;;

(defun term-write (string)
  "Write STRING to terminal."
  (write-string string *standard-output*)
  (finish-output *standard-output*))

(defun term-clear-line ()
  "Clear from cursor to end of line."
  (term-write (format nil "~C[K" +escape+)))

(defun term-move-cursor (n)
  "Move cursor N positions (negative = left, positive = right)."
  (cond
    ((plusp n)
     (term-write (format nil "~C[~DC" +escape+ n)))
    ((minusp n)
     (term-write (format nil "~C[~DD" +escape+ (- n))))))

(defun term-cursor-to-column (col)
  "Move cursor to column COL (0-based)."
  (term-write (format nil "~C~C[~DG" #\Return +escape+ (1+ col))))

(defun term-clear-screen ()
  "Clear screen and move cursor to top-left."
  (term-write (format nil "~C[2J~C[H" +escape+ +escape+)))

;;;
;;; Line Editor State
;;;

(defstruct editor-state
  "State for the line editor."
  (buffer (make-array 256 :element-type 'character
                          :adjustable t
                          :fill-pointer 0)
   :type (vector character))
  (cursor 0 :type fixnum)             ; Cursor position in buffer
  (prompt "" :type string)
  (prompt-length 0 :type fixnum)
  (history nil :type (or null history))
  (done nil :type boolean)
  (result nil))                       ; Result: string or :EOF

(defun editor-buffer-string (state)
  "Get the current buffer contents as a string."
  (coerce (editor-state-buffer state) 'string))

(defun editor-insert-char (state char)
  "Insert CHAR at cursor position."
  (let* ((buffer (editor-state-buffer state))
         (cursor (editor-state-cursor state))
         (len (length buffer)))
    ;; Make room
    (vector-push-extend #\Space buffer)
    ;; Shift characters right
    (loop for i from len downto (1+ cursor)
          do (setf (aref buffer i) (aref buffer (1- i))))
    ;; Insert character
    (setf (aref buffer cursor) char)
    ;; Move cursor
    (incf (editor-state-cursor state))))

(defun editor-delete-char-before (state)
  "Delete character before cursor (backspace)."
  (when (plusp (editor-state-cursor state))
    (let* ((buffer (editor-state-buffer state))
           (cursor (editor-state-cursor state))
           (len (length buffer)))
      ;; Shift characters left
      (loop for i from (1- cursor) below (1- len)
            do (setf (aref buffer i) (aref buffer (1+ i))))
      ;; Remove last character
      (decf (fill-pointer buffer))
      ;; Move cursor
      (decf (editor-state-cursor state)))))

(defun editor-delete-char-at (state)
  "Delete character at cursor (delete key)."
  (let* ((buffer (editor-state-buffer state))
         (cursor (editor-state-cursor state))
         (len (length buffer)))
    (when (< cursor len)
      ;; Shift characters left
      (loop for i from cursor below (1- len)
            do (setf (aref buffer i) (aref buffer (1+ i))))
      ;; Remove last character
      (decf (fill-pointer buffer)))))

(defun editor-set-buffer (state string)
  "Replace buffer contents with STRING."
  (let ((buffer (editor-state-buffer state)))
    (setf (fill-pointer buffer) 0)
    (loop for char across string
          do (vector-push-extend char buffer))
    (setf (editor-state-cursor state) (length buffer))))

(defun editor-kill-to-end (state)
  "Delete from cursor to end of line."
  (setf (fill-pointer (editor-state-buffer state))
        (editor-state-cursor state)))

(defun editor-kill-to-start (state)
  "Delete from start to cursor."
  (let* ((buffer (editor-state-buffer state))
         (cursor (editor-state-cursor state))
         (len (length buffer)))
    (loop for i from 0 below (- len cursor)
          do (setf (aref buffer i) (aref buffer (+ i cursor))))
    (setf (fill-pointer buffer) (- len cursor))
    (setf (editor-state-cursor state) 0)))

(defun editor-kill-word (state)
  "Delete word before cursor."
  (let* ((buffer (editor-state-buffer state))
         (cursor (editor-state-cursor state))
         (start cursor))
    ;; Skip whitespace
    (loop while (and (plusp start)
                     (member (aref buffer (1- start)) '(#\Space #\Tab)))
          do (decf start))
    ;; Skip word characters
    (loop while (and (plusp start)
                     (not (member (aref buffer (1- start)) '(#\Space #\Tab))))
          do (decf start))
    ;; Delete from start to cursor
    (when (< start cursor)
      (let ((len (length buffer)))
        (loop for i from start below (- len (- cursor start))
              do (setf (aref buffer i) (aref buffer (+ i (- cursor start)))))
        (decf (fill-pointer buffer) (- cursor start))
        (setf (editor-state-cursor state) start)))))

;;;
;;; Display Refresh
;;;

(defun editor-refresh (state)
  "Redraw the current line."
  (let ((buffer (editor-state-buffer state))
        (cursor (editor-state-cursor state))
        (prompt (editor-state-prompt state)))
    ;; Move to start of line and clear
    (term-write (format nil "~C" #\Return))
    (term-clear-line)
    ;; Write prompt and buffer
    (term-write prompt)
    (term-write (coerce buffer 'string))
    ;; Position cursor
    (let ((target-col (+ (length prompt) cursor)))
      (term-cursor-to-column target-col))))

;;;
;;; Key Handlers
;;;

(defun handle-key (state key)
  "Handle a key press, updating STATE."
  (cond
    ;; Regular character
    ((characterp key)
     (when (and (graphic-char-p key)
                (>= (char-code key) 32))
       (editor-insert-char state key)
       (editor-refresh state)))

    ;; Enter - done
    ((eq key :enter)
     (setf (editor-state-done state) t)
     (setf (editor-state-result state) (editor-buffer-string state))
     (term-write (format nil "~%")))

    ;; EOF (Ctrl+D)
    ((eq key :eof)
     (if (zerop (length (editor-state-buffer state)))
         (progn
           (setf (editor-state-done state) t)
           (setf (editor-state-result state) :eof))
         ;; If buffer non-empty, treat as delete
         (progn
           (editor-delete-char-at state)
           (editor-refresh state))))

    ;; Interrupt (Ctrl+C)
    ((eq key :interrupt)
     (setf (editor-state-done state) t)
     (setf (editor-state-result state) :interrupt)
     (term-write "^C~%"))

    ;; Backspace
    ((eq key :backspace)
     (editor-delete-char-before state)
     (editor-refresh state))

    ;; Delete
    ((eq key :delete)
     (editor-delete-char-at state)
     (editor-refresh state))

    ;; Left arrow
    ((eq key :left)
     (when (plusp (editor-state-cursor state))
       (decf (editor-state-cursor state))
       (term-move-cursor -1)))

    ;; Right arrow
    ((eq key :right)
     (when (< (editor-state-cursor state)
              (length (editor-state-buffer state)))
       (incf (editor-state-cursor state))
       (term-move-cursor 1)))

    ;; Up arrow - history previous
    ((eq key :up)
     (when (editor-state-history state)
       (let ((prev (history-previous (editor-state-history state)
                                     (editor-buffer-string state))))
         (when prev
           (editor-set-buffer state prev)
           (editor-refresh state)))))

    ;; Down arrow - history next
    ((eq key :down)
     (when (editor-state-history state)
       (let ((next (history-next (editor-state-history state))))
         (when next
           (editor-set-buffer state next)
           (editor-refresh state)))))

    ;; Home
    ((eq key :home)
     (setf (editor-state-cursor state) 0)
     (editor-refresh state))

    ;; End
    ((eq key :end)
     (setf (editor-state-cursor state)
           (length (editor-state-buffer state)))
     (editor-refresh state))

    ;; Kill to end (Ctrl+K)
    ((eq key :kill-to-end)
     (editor-kill-to-end state)
     (editor-refresh state))

    ;; Kill to start (Ctrl+U)
    ((eq key :kill-to-start)
     (editor-kill-to-start state)
     (editor-refresh state))

    ;; Kill word (Ctrl+W)
    ((eq key :kill-word)
     (editor-kill-word state)
     (editor-refresh state))

    ;; Clear screen (Ctrl+L)
    ((eq key :clear-screen)
     (term-clear-screen)
     (editor-refresh state))

    ;; Escape - ignore
    ((eq key :escape)
     nil)

    ;; Unknown - ignore
    (t nil)))

;;;
;;; Main Entry Point
;;;

(defun linedit (&key (prompt "") (history nil) (stream *standard-input*))
  "Read a line with editing support.

   PROMPT - String to display before input
   HISTORY - History object for navigation (optional)
   STREAM - Input stream (default *standard-input*)

   Returns the line as a string, or NIL on EOF/interrupt."
  ;; Check if we can use the terminal
  (unless (interactive-stream-p stream)
    ;; Fall back to simple read-line for non-interactive streams
    (when (plusp (length prompt))
      (write-string prompt)
      (finish-output))
    (return-from linedit (read-line stream nil nil)))

  (let ((state (make-editor-state
                :prompt prompt
                :prompt-length (length prompt)
                :history history))
        (raw-mode-ok nil))
    ;; Reset history position if we have history
    (when history
      (history-reset-position history))

    ;; Display initial prompt
    (term-write prompt)
    (finish-output)

    ;; Try to enable raw mode
    (setf raw-mode-ok (terminal-raw-mode))

    (unwind-protect
         (if raw-mode-ok
             ;; Raw mode - read character by character
             (loop until (editor-state-done state)
                   for key = (read-key stream)
                   do (handle-key state key))
             ;; Fallback - just read a line
             (let ((line (read-line stream nil nil)))
               (setf (editor-state-done state) t)
               (setf (editor-state-result state) (or line :eof))))
      ;; Always restore terminal
      (when raw-mode-ok
        (terminal-restore)))

    ;; Return result
    (let ((result (editor-state-result state)))
      (cond
        ((stringp result) result)
        ((eq result :eof) nil)
        ((eq result :interrupt) nil)
        (t nil)))))
