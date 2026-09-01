;; EXPORT_SWEEP_LTM1300 - batch-exports the LTM 1300's 4 boom configs
;; (T = main boom only, TK/TF/TN = 3 jib attachments), each via the same
;; decoupled sweep approach as the LTM 1650 pipeline: main boom
;; (length x angle) with jib fixed at a reference pose, plus jib (length
;; x angle, where the jib has its own angle control) swept on its own
;; with the main boom fixed at a reference pose. See
;; cad/boom-rig-pipeline/README.md for why (full cross product would be
;; enormous).
;;
;; Property names are THIS crane's own (from DUMPDYNPROPS) - different
;; from the LTM 1650's. Master config switch here is "Состав стрелы"
;; with only 4 states (T/TK/TF/TN), much smaller than the 1650's 20.
;; Jib TK has no separate angle property in the dump - swept as
;; length-only; if that turns out wrong (visually the jib doesn't
;; actually move), tell me and I'll adjust.
;;
;; IMPORTANT SAFETY NOTES - READ BEFORE RUNNING:
;;   1. Work on a COPY of the DXF, never your original master file.
;;   2. Do NOT save the drawing after running this. It restores the
;;      block's original property values at the end of each config, but
;;      don't rely on that - just close without saving when you're done.
;;   3. Edit *OUTDIR* below to a real folder before running.
;;   4. Writes .dwg files - convert the whole output folder to .dxf with
;;      ODA File Converter afterward, same as the 1650 pipeline.
;;   5. Run ONE config at a time, or EXPORTSWEEP-LTM1300-ALL for
;;      everything in one sitting (will take a while - see the printed
;;      per-config pose counts).
;;
;; HOW TO RUN:
;;   (load "export_sweep_ltm1300.lsp")
;;   EXPORTSWEEP-LTM1300-T
;;   EXPORTSWEEP-LTM1300-TK
;;   EXPORTSWEEP-LTM1300-TF
;;   EXPORTSWEEP-LTM1300-TN
;;   -- or --
;;   EXPORTSWEEP-LTM1300-ALL

;; ===== OUTPUT FOLDER =====
(setq *OUTDIR* (strcat (getenv "USERPROFILE") "/Documents/export_ltm1300/"))
;; =========================================

(setq *PI* 3.14159265358979)

;; All 15 real main boom lengths (from "Основная стрела" AllowedValues)
(setq *LENGTHS*
  '(("14.7" . "Стрела 14,7 м") ("19.6" . "Стрела 19,6 м") ("24.4" . "Стрела 24,4 м")
    ("29.3" . "Стрела 29,3 м") ("34.2" . "Стрела 34,2 м") ("39.0" . "Стрела 39,0 м")
    ("43.9" . "Стрела 43,9 м") ("48.7" . "Стрела 48,7 м") ("53.6" . "Стрела 53,6 м")
    ("58.5" . "Стрела 58,5 м") ("63.3" . "Стрела 63,3 м") ("68.2" . "Стрела 68,2 м")
    ("73.1" . "Стрела 73,1 м") ("77.2" . "Стрела 77,2 м") ("78.0" . "Стрела 78,0 м"))
)
(setq *ANGLES-FULL* '(0 10 20 30 40 50 60 70 80))

;; Reference main-boom pose used while sweeping a jib on its own.
(setq *REF-LENGTH* (nth 7 *LENGTHS*))  ;; "48.7"
(setq *REF-ANGLE* 40)

;; Jib TK: all 7 real catalog lengths (no separate angle property found)
(setq *JIB-TK-LENGTHS*
  '(("5.5" . "Гусек 5.5 м") ("12.5" . "Гусек 12.5 м") ("19.5" . "Гусек 19.5 м")
    ("21.0" . "Гусек 21.0 м") ("26.5" . "Гусек 26.5 м") ("28.0" . "Гусек 28.0 м")
    ("35.0" . "Гусек 35.0 м"))
)
;; Jib TF: all 9 real catalog lengths
(setq *JIB-TF-LENGTHS*
  '(("14.0" . "Гусек 14.0 м") ("17.5" . "Гусек 17.5 м") ("21.0" . "Гусек 21.0 м")
    ("24.5" . "Гусек 24.5 м") ("28.0" . "Гусек 28.0 м") ("31.5" . "Гусек 31.5 м")
    ("35.0" . "Гусек 35.0 м") ("38.5" . "Гусек 38.5 м") ("42.0" . "Гусек 42.0 м"))
)
;; Jib TN: all 16 real catalog lengths
(setq *JIB-TN-LENGTHS*
  '(("17.5" . "Гусек 17.5 м") ("21.0" . "Гусек 21.0 м") ("24.5" . "Гусек 24.5 м")
    ("28.0" . "Гусек 28.0 м") ("31.5" . "Гусек 31.5 м") ("35.0" . "Гусек 35.0 м")
    ("38.5" . "Гусек 38.5 м") ("42.0" . "Гусек 42.0 м") ("45.5" . "Гусек 45.5 м")
    ("49.0" . "Гусек 49.0 м") ("52.5" . "Гусек 52.5 м") ("56.0" . "Гусек 56.0 м")
    ("59.5" . "Гусек 59.5 м") ("63.0" . "Гусек 63.0 м") ("66.5" . "Гусек 66.5 м")
    ("70.0" . "Гусек 70.0 м"))
)
;; Jib angle sampling for TF/TN (same guess-and-skip-invalid approach as
;; the 1650 pipeline - AutoCAD rejecting an out-of-range value just skips
;; that one pose, doesn't kill the sweep).
(setq *JIB-ANGLES* '(0 5 10 15 20 25 30 35 40))

;; ---------- helpers (same proven engine as export_sweep_variants.lsp) ----------

(defun find-crane-obj ( / ss n i ent obj isdyn found)
  (setq ss (ssget "_X" '((0 . "INSERT"))))
  (setq found nil)
  (if ss
    (progn
      (setq n (sslength ss))
      (setq i 0)
      (while (and (< i n) (not found))
        (setq ent (ssname ss i))
        (setq obj (vl-catch-all-apply 'vlax-ename->vla-object (list ent)))
        (if (not (vl-catch-all-error-p obj))
          (progn
            (setq isdyn (vl-catch-all-apply 'vlax-get (list obj 'IsDynamicBlock)))
            (if (and (not (vl-catch-all-error-p isdyn))
                     (or (eq isdyn :vlax-true) (and (numberp isdyn) (/= isdyn 0))))
              (setq found obj)
            )
          )
        )
        (setq i (1+ i))
      )
    )
  )
  found
)

(defun get-prop (obj pname / props prop result)
  (setq props (vlax-invoke obj 'GetDynamicBlockProperties))
  (setq result nil)
  (foreach prop props
    (if (equal (vlax-get prop 'PropertyName) pname)
      (setq result prop)
    )
  )
  result
)

(defun safe-put (prop val label / r)
  (if (null prop)
    nil
    (progn
      (setq r (vl-catch-all-apply 'vlax-put (list prop 'Value val)))
      (if (vl-catch-all-error-p r)
        (progn
          (princ (strcat "\n    SKIP (" label "): " (vl-catch-all-error-message r)))
          nil
        )
        T
      )
    )
  )
)

;; Cancel (not blank-Enter) any leftover pending prompt. A blank "" at an
;; already-idle Command: prompt REPEATS THE LAST COMMAND in AutoCAD - if
;; CMDACTIVE briefly reads >0 right after a real command already
;; finished (a timing quirk, not a genuinely stuck prompt), sending ""
;; can silently re-trigger wblock/erase a second time with nothing there
;; to answer its prompts, corrupting or wiping the file just written.
;; Escape (Ctrl+C) cancels instead of repeating, so it's safe either way.
(defun flush-pending-command ( / n)
  (setq n 0)
  (while (and (> (getvar "CMDACTIVE") 0) (< n 10))
    (command "\x03\x03")
    (setq n (1+ n))
  )
)

(defun export-current-pose (crane-obj fname / copyobj copyename ss ok)
  (setq copyobj (vl-catch-all-apply 'vlax-invoke (list crane-obj 'Copy)))
  (if (vl-catch-all-error-p copyobj)
    (progn
      (princ (strcat "\n    ERROR copying block: " (vl-catch-all-error-message copyobj)))
      nil
    )
    (progn
      (setq copyename (vlax-vla-object->ename copyobj))
      (setq ss (ssadd))
      (setq ss (ssadd copyename ss))
      (vl-catch-all-apply 'vl-file-delete (list fname))

      ;; Call command DIRECTLY, not through (vl-catch-all-apply 'command
      ;; (list ...)) - command is a variadic/special AutoLISP function
      ;; and does not reliably behave the same when invoked indirectly
      ;; through apply-style argument passing, especially with a
      ;; selection-set argument like ss. This was the actual root cause
      ;; of files never landing on disk despite the sweep reporting
      ;; success - confirmed by a minimal isolated test using a bare
      ;; direct command call, which worked every time. export-current-
      ;; pose is already wrapped in vl-catch-all-apply at every call
      ;; site, so a genuine error here still can't kill the whole sweep.
      (command "_.-wblock" fname "" (list 0.0 0.0 0.0) ss "")
      (flush-pending-command)

      (command "_.erase" ss "")
      (flush-pending-command)

      ;; ground truth: trust only whether the file actually exists
      (setq ok (findfile fname))
      (if ok
        (princ (strcat "\n    -> " fname))
        (princ (strcat "\n    FAILED (no file written): " fname))
      )
      (if ok T nil)
    )
  )
)

;; ---------- the main worker ----------
;; config-name: exact Visibility/lookup value for "Состав стрелы" (T/TK/TF/TN)
;; jib-lengths: the length-pair list for this config's jib (nil if none, i.e. base T)
;; jib-prop-name / jib-angle-prop-name: property names for this config's jib
;;   (jib-angle-prop-name nil if that jib has no angle control, e.g. TK)
(defun run-ltm1300-sweep (config-name jib-lengths jib-prop-name jib-angle-prop-name
                           / crane-obj cfgprop lenprop angprop jibprop jangprop
                             orig-cfg orig-len orig-ang orig-jib orig-jang
                             total done skipped len-pair angle-deg jlen-pair fname)
  (if (not (vl-file-directory-p *OUTDIR*)) (vl-mkdir *OUTDIR*))
  (setq crane-obj (find-crane-obj))
  (if (null crane-obj)
    (princ "\nNo dynamic block found in modelspace. Aborting.")
    (progn
      (setq cfgprop (get-prop crane-obj "Состав стрелы"))
      (setq lenprop (get-prop crane-obj "Основная стрела"))
      (setq angprop (get-prop crane-obj "Наклон стрелы T"))
      (setq jibprop (if jib-prop-name (get-prop crane-obj jib-prop-name) nil))
      (setq jangprop (if jib-angle-prop-name (get-prop crane-obj jib-angle-prop-name) nil))

      (if (or (null cfgprop) (null lenprop) (null angprop))
        (princ "\nERROR: could not find Состав стрелы / Основная стрела / Наклон стрелы T. Aborting.")
        (progn
          (setq orig-cfg (vlax-get cfgprop 'Value))
          (setq orig-len (vlax-get lenprop 'Value))
          (setq orig-ang (vlax-get angprop 'Value))
          (setq orig-jib (if jibprop (vlax-get jibprop 'Value) nil))
          (setq orig-jang (if jangprop (vlax-get jangprop 'Value) nil))

          (if (not (safe-put cfgprop config-name "Состав стрелы"))
            (princ (strcat "\nERROR: could not switch to " config-name ". Aborting this config."))
            (progn
              (vl-catch-all-apply (function (lambda () (command "_.regen"))) nil)
              (setq total 0) (setq done 0) (setq skipped 0)

              ;; ---- pass 1: main boom sweep, jib fixed at reference ----
              (princ (strcat "\n=== " config-name ": main boom sweep ==="))
              (if jibprop (safe-put jibprop (cdr (nth 0 jib-lengths)) "ref jib length"))
              (if jangprop (safe-put jangprop 0.0 "ref jib angle"))
              (vl-catch-all-apply (function (lambda () (command "_.regen"))) nil)

              (foreach len-pair *LENGTHS*
                (foreach angle-deg *ANGLES-FULL*
                  (setq total (1+ total))
                  (if (and (safe-put lenprop (cdr len-pair) "main length")
                           (safe-put angprop (* angle-deg (/ *PI* 180.0)) "main angle"))
                    (progn
                      (vl-catch-all-apply (function (lambda () (command "_.regen"))) nil)
                      (setq fname (strcat *OUTDIR* "pose_" config-name "_L" (car len-pair)
                                           "_A" (itoa (fix angle-deg)) ".dwg"))
                      (if (vl-catch-all-apply 'export-current-pose (list crane-obj fname))
                        (setq done (1+ done)) (setq skipped (1+ skipped)))
                    )
                    (setq skipped (1+ skipped))
                  )
                )
              )

              ;; ---- pass 2: jib sweep, main boom fixed at reference ----
              (if jibprop
                (progn
                  (princ (strcat "\n=== " config-name ": jib sweep (main boom fixed) ==="))
                  (safe-put lenprop (cdr *REF-LENGTH*) "ref main length")
                  (safe-put angprop (* *REF-ANGLE* (/ *PI* 180.0)) "ref main angle")
                  (vl-catch-all-apply (function (lambda () (command "_.regen"))) nil)
                  (if jangprop
                    ;; jib has its own angle control - sweep length x angle
                    (foreach jlen-pair jib-lengths
                      (foreach angle-deg *JIB-ANGLES*
                        (setq total (1+ total))
                        (if (and (safe-put jibprop (cdr jlen-pair) "jib length")
                                 (safe-put jangprop (* angle-deg (/ *PI* 180.0)) "jib angle"))
                          (progn
                            (vl-catch-all-apply (function (lambda () (command "_.regen"))) nil)
                            (setq fname (strcat *OUTDIR* "pose_" config-name "_JL" (car jlen-pair)
                                                 "_JA" (itoa (fix angle-deg)) ".dwg"))
                            (if (vl-catch-all-apply 'export-current-pose (list crane-obj fname))
                              (setq done (1+ done)) (setq skipped (1+ skipped)))
                          )
                          (setq skipped (1+ skipped))
                        )
                      )
                    )
                    ;; no angle control on this jib - length only
                    (foreach jlen-pair jib-lengths
                      (setq total (1+ total))
                      (if (safe-put jibprop (cdr jlen-pair) "jib length")
                        (progn
                          (vl-catch-all-apply (function (lambda () (command "_.regen"))) nil)
                          (setq fname (strcat *OUTDIR* "pose_" config-name "_JL" (car jlen-pair) ".dwg"))
                          (if (vl-catch-all-apply 'export-current-pose (list crane-obj fname))
                            (setq done (1+ done)) (setq skipped (1+ skipped)))
                        )
                        (setq skipped (1+ skipped))
                      )
                    )
                  )
                )
              )

              ;; ---- restore everything ----
              (safe-put cfgprop orig-cfg "restore Состав стрелы")
              (safe-put lenprop orig-len "restore main length")
              (safe-put angprop orig-ang "restore main angle")
              (if (and jibprop orig-jib) (safe-put jibprop orig-jib "restore jib length"))
              (if (and jangprop orig-jang) (safe-put jangprop orig-jang "restore jib angle"))
              (vl-catch-all-apply (function (lambda () (command "_.regen"))) nil)

              (princ "\n----------------------------------------")
              (princ (strcat "\n" config-name " done: " (itoa done) " exported, "
                              (itoa skipped) " skipped, out of " (itoa total) " attempted."))
              (princ "\nOriginal property values restored. Do NOT save this drawing.")
            )
          )
        )
      )
    )
  )
  (princ)
)

;; ---------- per-config commands ----------

(defun c:EXPORTSWEEP-LTM1300-T ()  (run-ltm1300-sweep "T"  nil nil nil) )
(defun c:EXPORTSWEEP-LTM1300-TK () (run-ltm1300-sweep "TK" *JIB-TK-LENGTHS* "Гусек ТК" nil) )
(defun c:EXPORTSWEEP-LTM1300-TF () (run-ltm1300-sweep "TF" *JIB-TF-LENGTHS* "Гусек TF" "Наклон гуська TF") )
(defun c:EXPORTSWEEP-LTM1300-TN () (run-ltm1300-sweep "TN" *JIB-TN-LENGTHS* "Гусек TN" "Наклон гуська TN") )

(defun c:EXPORTSWEEP-LTM1300-ALL ()
  (princ "\n\n########## STARTING: T ##########")
  (run-ltm1300-sweep "T" nil nil nil)
  (princ "\n\n########## STARTING: TK ##########")
  (run-ltm1300-sweep "TK" *JIB-TK-LENGTHS* "Гусек ТК" nil)
  (princ "\n\n########## STARTING: TF ##########")
  (run-ltm1300-sweep "TF" *JIB-TF-LENGTHS* "Гусек TF" "Наклон гуська TF")
  (princ "\n\n########## STARTING: TN ##########")
  (run-ltm1300-sweep "TN" *JIB-TN-LENGTHS* "Гусек TN" "Наклон гуська TN")
  (princ "\n\n########## ALL 4 CONFIGS DONE ##########")
  (princ)
)

(princ "\nEXPORT_SWEEP_LTM1300 loaded.")
(princ (strcat "\nOutput folder: " *OUTDIR*))
(princ "\nRun everything in one go:")
(princ "\n  EXPORTSWEEP-LTM1300-ALL")
(princ "\nOr one config at a time:")
(princ "\n  EXPORTSWEEP-LTM1300-T  EXPORTSWEEP-LTM1300-TK  EXPORTSWEEP-LTM1300-TF  EXPORTSWEEP-LTM1300-TN")
(princ)
