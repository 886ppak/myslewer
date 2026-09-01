;; EXPORT_SWEEP_VARIANTS - batch-exports the crane's other 9 T3-family
;; configs (T3Y, T3N, T3NY, T3NH, T3NYH, T3F, T3FH, T3YVEF, T3YVEFH),
;; each via a DECOUPLED sweep: the main boom (length x angle, same 90
;; poses as the base T3 sweep) with jib/guy fixed at a reference pose,
;; PLUS the jib (length x angle) or guy (angle only) swept on its own
;; with the main boom fixed at a reference pose. Not a full cross
;; product - see cad/boom-rig-pipeline/README.md for why (the full
;; cross product for even one jib config is 17,000+ poses).
;;
;; Standalone from export_sweep.lsp (T3 base config, already done) -
;; load this file on its own, doesn't need export_sweep.lsp loaded too.
;;
;; IMPORTANT SAFETY NOTES - READ BEFORE RUNNING:
;;   1. Work on a COPY of the DXF, never your original master file.
;;   2. Do NOT save the drawing after running this. It restores the
;;      block's original property values at the end of each config, but
;;      don't rely on that - just close without saving when you're done.
;;   3. Edit *OUTDIR* below to a real folder before running.
;;   4. Writes .dwg files - convert the whole output folder to .dxf with
;;      ODA File Converter afterward, same as before.
;;   5. This is a LOT of poses (roughly 2,200 across all 9 configs -
;;      see the per-config counts printed by each command below). Run
;;      ONE config at a time, not all 9 in one sitting - each command
;;      below is independent and safe to run in a separate session.
;;   6. Jib angle (Наклон гуська) allowed range is NOT documented
;;      anywhere available to build this from - the *JIB-ANGLES* list
;;      below is a starting guess (0-40 deg). Any angle AutoCAD rejects
;;      is skipped automatically (logged, not fatal) - check the
;;      "SKIPPED" count in the summary at the end. If a lot of jib-angle
;;      poses get skipped, tell me the printed error message and the
;;      real range and I'll fix the list.
;;
;; HOW TO RUN (pick ONE config, check its output, then move to the next):
;;   (load "export_sweep_variants.lsp")
;;   EXPORTSWEEP-T3Y
;;   EXPORTSWEEP-T3N
;;   EXPORTSWEEP-T3NY
;;   EXPORTSWEEP-T3NH
;;   EXPORTSWEEP-T3NYH
;;   EXPORTSWEEP-T3F
;;   EXPORTSWEEP-T3FH
;;   EXPORTSWEEP-T3YVEF
;;   EXPORTSWEEP-T3YVEFH

;; ===== OUTPUT FOLDER =====
(setq *OUTDIR* (strcat (getenv "USERPROFILE") "/Documents/export/"))
;; =========================================

(setq *PI* 3.14159265358979)

;; All 10 real T3 boom lengths (same as export_sweep.lsp)
(setq *LENGTHS*
  '(("16.6" . "Стрела 16.6 м") ("22.4" . "Стрела 22.4 м") ("28.2" . "Стрела 28.2 м")
    ("33.9" . "Стрела 33.9 м") ("39.7" . "Стрела 39.7 м") ("45.3" . "Стрела 45.3 м")
    ("51.0" . "Стрела 51.0 м") ("52.0" . "Стрела 52.0 м") ("53.0" . "Стрела 53.0 м")
    ("54.0" . "Стрела 54.0 м"))
)
(setq *ANGLES-FULL* '(0 10 20 30 40 50 60 70 80))

;; Reference main-boom pose used while sweeping jib/guy on their own
;; (a middling length + angle - arbitrary but consistent across configs).
(setq *REF-LENGTH* (nth 3 *LENGTHS*))  ;; "33.9"
(setq *REF-ANGLE* 40)

;; Jib N: all 21 real catalog lengths (from DUMPDYNPROPS's AllowedValues
;; on "Гусек N"). Label is just the numeric part for filenames.
(setq *JIB-N-LENGTHS*
  '(("21.0" . "Гусек 21.0 м") ("24.5" . "Гусек 24.5 м") ("28.0" . "Гусек 28.0 м")
    ("31.5" . "Гусек 31.5 м") ("35.0" . "Гусек 35.0 м") ("38.5" . "Гусек 38.5 м")
    ("42.0" . "Гусек 42.0 м") ("45.5" . "Гусек 45.5 м") ("49.0" . "Гусек 49.0 м")
    ("52.5" . "Гусек 52.5 м") ("56.0" . "Гусек 56.0 м") ("59.5" . "Гусек 59.5 м")
    ("63.0" . "Гусек 63.0 м") ("66.5" . "Гусек 66.5 м") ("70.0" . "Гусек 70.0 м")
    ("73.5" . "Гусек 73.5 м") ("77.0" . "Гусек 77.0 м") ("80.5" . "Гусек 80.5 м")
    ("84.0" . "Гусек 84.0 м") ("87.5" . "Гусек 87.5 м") ("91.0" . "Гусек 91.0 м"))
)
;; Jib F: all 17 real catalog lengths (from "Гусек F")
(setq *JIB-F-LENGTHS*
  '(("6.0" . "Гусек 6.0 м") ("9.5" . "Гусек 9.5 м") ("13.0" . "Гусек 13.0 м")
    ("16.5" . "Гусек 16.5 м") ("20.0" . "Гусек 20.0 м") ("23.5" . "Гусек 23.5 м")
    ("27.0" . "Гусек 27.0 м") ("30.5" . "Гусек 30.5 м") ("34.0" . "Гусек 34.0 м")
    ("37.5" . "Гусек 37.5 м") ("41.0" . "Гусек 41.0 м") ("44.5" . "Гусек 44.5 м")
    ("48.0" . "Гусек 48.0 м") ("51.5" . "Гусек 51.5 м") ("55.0" . "Гусек 55.0 м")
    ("58.5" . "Гусек 58.5 м") ("62.0" . "Гусек 62.0 м"))
)
;; Jib angle sampling - SEE SAFETY NOTE 6 ABOVE, this range is a guess.
(setq *JIB-ANGLES* '(0 5 10 15 20 25 30 35 40))

;; Guy/stay angle (Расчалы) - all 3 real options
(setq *GUY-ANGLES*
  '(("30" . "30 град.") ("45" . "45 град.") ("60" . "60 град."))
)

;; ---------- helpers ----------

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

;; safe set: returns T on success, nil (and prints why) on failure -
;; used for every property set so one bad value (e.g. an out-of-range
;; jib angle) just gets skipped instead of killing the whole sweep.
(defun safe-put (prop val label / r)
  (setq r (vl-catch-all-apply 'vlax-put (list prop 'Value val)))
  (if (vl-catch-all-error-p r)
    (progn
      (princ (strcat "\n    SKIP (" label "): " (vl-catch-all-error-message r)))
      nil
    )
    T
  )
)

;; Some configs (anything with a jib/heavy-hook attached) pull in nested
;; block definitions the plain T3 sweep never touched, which can pop an
;; extra confirmation prompt (e.g. block-redefinition) WBLOCK's normal
;; sequence doesn't have - a fixed-length (command ...) arg list runs out
;; mid-sequence when that happens, leaving the command dangling and every
;; call after it errors with "bad order function: COMMAND". Flush
;; whatever's left pending (accepting defaults) instead of assuming a
;; fixed prompt count.
(defun flush-pending-command ( / n)
  (setq n 0)
  (while (and (> (getvar "CMDACTIVE") 0) (< n 10))
    (command "")
    (setq n (1+ n))
  )
)

(defun export-current-pose (crane-obj fname / copyobj copyename ss)
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
      (command "_.-wblock" fname "" (list 0.0 0.0 0.0) ss "")
      (flush-pending-command)
      (vl-catch-all-apply 'command (list "_.erase" ss ""))
      (flush-pending-command)
      (princ (strcat "\n    -> " fname))
      T
    )
  )
)

;; ---------- the main worker ----------
;; config-name: e.g. "T3N" (must exactly match a Visibility1 AllowedValue)
;; has-jib-n / has-jib-f / has-guy: T/nil, decided by the caller from the
;; config name's letters (N -> jib N, F -> jib F, Y -> guy)
(defun run-config-sweep (config-name has-jib-n has-jib-f has-guy
                          / crane-obj visprop lenprop angprop jnprop jfprop japrop gprop
                            orig-vis orig-len orig-ang orig-jn orig-jf orig-ja orig-guy
                            total done skipped len-pair angle-deg jlen-pair guy-pair fname)
  (if (not (vl-file-directory-p *OUTDIR*)) (vl-mkdir *OUTDIR*))
  (setq crane-obj (find-crane-obj))
  (if (null crane-obj)
    (princ "\nNo dynamic block found in modelspace. Aborting.")
    (progn
      (setq visprop (get-prop crane-obj "Visibility1"))
      (setq lenprop (get-prop crane-obj "Стрела T3"))
      (setq angprop (get-prop crane-obj "Наклон основной стрелы"))
      (setq jnprop  (get-prop crane-obj "Гусек N"))
      (setq jfprop  (get-prop crane-obj "Гусек F"))
      (setq japrop  (get-prop crane-obj "Наклон гуська"))
      (setq gprop   (get-prop crane-obj "Расчалы"))

      (if (null visprop)
        (princ "\nERROR: could not find Visibility1 property. Aborting.")
        (progn
          (setq orig-vis (vlax-get visprop 'Value))
          (setq orig-len (if lenprop (vlax-get lenprop 'Value) nil))
          (setq orig-ang (if angprop (vlax-get angprop 'Value) nil))
          (setq orig-jn  (if jnprop (vlax-get jnprop 'Value) nil))
          (setq orig-jf  (if jfprop (vlax-get jfprop 'Value) nil))
          (setq orig-ja  (if japrop (vlax-get japrop 'Value) nil))
          (setq orig-guy (if gprop (vlax-get gprop 'Value) nil))

          (if (not (safe-put visprop config-name "Visibility1"))
            (princ (strcat "\nERROR: could not switch to " config-name ". Aborting this config."))
            (progn
              (progn (command "_.regen") (flush-pending-command))
              (setq total 0) (setq done 0) (setq skipped 0)

              ;; ---- pass 1: main boom sweep, jib/guy fixed at reference ----
              (princ (strcat "\n=== " config-name ": main boom sweep (jib/guy fixed) ==="))
              (if has-jib-n (safe-put jnprop (cdr (nth 0 *JIB-N-LENGTHS*)) "ref jib N"))
              (if has-jib-f (safe-put jfprop (cdr (nth 0 *JIB-F-LENGTHS*)) "ref jib F"))
              (if (or has-jib-n has-jib-f) (safe-put japrop 0.0 "ref jib angle"))
              (if has-guy (safe-put gprop (cdr (nth 0 *GUY-ANGLES*)) "ref guy angle"))
              (progn (command "_.regen") (flush-pending-command))

              (foreach len-pair *LENGTHS*
                (foreach angle-deg *ANGLES-FULL*
                  (setq total (1+ total))
                  (if (and (safe-put lenprop (cdr len-pair) "main length")
                           (safe-put angprop (* angle-deg (/ *PI* 180.0)) "main angle"))
                    (progn
                      (progn (command "_.regen") (flush-pending-command))
                      (setq fname (strcat *OUTDIR* "pose_" config-name "_L" (car len-pair)
                                           "_A" (itoa (fix angle-deg)) ".dwg"))
                      (if (export-current-pose crane-obj fname) (setq done (1+ done)) (setq skipped (1+ skipped)))
                    )
                    (setq skipped (1+ skipped))
                  )
                )
              )

              ;; ---- pass 2: jib N sweep, main boom fixed at reference ----
              (if has-jib-n
                (progn
                  (princ (strcat "\n=== " config-name ": jib N sweep (main boom fixed) ==="))
                  (safe-put lenprop (cdr *REF-LENGTH*) "ref main length")
                  (safe-put angprop (* *REF-ANGLE* (/ *PI* 180.0)) "ref main angle")
                  (progn (command "_.regen") (flush-pending-command))
                  (foreach jlen-pair *JIB-N-LENGTHS*
                    (foreach angle-deg *JIB-ANGLES*
                      (setq total (1+ total))
                      (if (and (safe-put jnprop (cdr jlen-pair) "jib N length")
                               (safe-put japrop (* angle-deg (/ *PI* 180.0)) "jib angle"))
                        (progn
                          (progn (command "_.regen") (flush-pending-command))
                          (setq fname (strcat *OUTDIR* "pose_" config-name "_JL" (car jlen-pair)
                                               "_JA" (itoa (fix angle-deg)) ".dwg"))
                          (if (export-current-pose crane-obj fname) (setq done (1+ done)) (setq skipped (1+ skipped)))
                        )
                        (setq skipped (1+ skipped))
                      )
                    )
                  )
                )
              )

              ;; ---- pass 2b: jib F sweep, main boom fixed at reference ----
              (if has-jib-f
                (progn
                  (princ (strcat "\n=== " config-name ": jib F sweep (main boom fixed) ==="))
                  (safe-put lenprop (cdr *REF-LENGTH*) "ref main length")
                  (safe-put angprop (* *REF-ANGLE* (/ *PI* 180.0)) "ref main angle")
                  (progn (command "_.regen") (flush-pending-command))
                  (foreach jlen-pair *JIB-F-LENGTHS*
                    (foreach angle-deg *JIB-ANGLES*
                      (setq total (1+ total))
                      (if (and (safe-put jfprop (cdr jlen-pair) "jib F length")
                               (safe-put japrop (* angle-deg (/ *PI* 180.0)) "jib angle"))
                        (progn
                          (progn (command "_.regen") (flush-pending-command))
                          (setq fname (strcat *OUTDIR* "pose_" config-name "_JL" (car jlen-pair)
                                               "_JA" (itoa (fix angle-deg)) ".dwg"))
                          (if (export-current-pose crane-obj fname) (setq done (1+ done)) (setq skipped (1+ skipped)))
                        )
                        (setq skipped (1+ skipped))
                      )
                    )
                  )
                )
              )

              ;; ---- pass 3: guy angle sweep, main boom (+ jib if any) fixed ----
              (if has-guy
                (progn
                  (princ (strcat "\n=== " config-name ": guy angle sweep (main boom fixed) ==="))
                  (safe-put lenprop (cdr *REF-LENGTH*) "ref main length")
                  (safe-put angprop (* *REF-ANGLE* (/ *PI* 180.0)) "ref main angle")
                  (progn (command "_.regen") (flush-pending-command))
                  (foreach guy-pair *GUY-ANGLES*
                    (setq total (1+ total))
                    (if (safe-put gprop (cdr guy-pair) "guy angle")
                      (progn
                        (progn (command "_.regen") (flush-pending-command))
                        (setq fname (strcat *OUTDIR* "pose_" config-name "_G" (car guy-pair) ".dwg"))
                        (if (export-current-pose crane-obj fname) (setq done (1+ done)) (setq skipped (1+ skipped)))
                      )
                      (setq skipped (1+ skipped))
                    )
                  )
                )
              )

              ;; ---- restore everything ----
              (safe-put visprop orig-vis "restore Visibility1")
              (if (and lenprop orig-len) (safe-put lenprop orig-len "restore main length"))
              (if (and angprop orig-ang) (safe-put angprop orig-ang "restore main angle"))
              (if (and jnprop orig-jn) (safe-put jnprop orig-jn "restore jib N"))
              (if (and jfprop orig-jf) (safe-put jfprop orig-jf "restore jib F"))
              (if (and japrop orig-ja) (safe-put japrop orig-ja "restore jib angle"))
              (if (and gprop orig-guy) (safe-put gprop orig-guy "restore guy angle"))
              (progn (command "_.regen") (flush-pending-command))

              (princ "\n----------------------------------------")
              (princ (strcat "\n" config-name " done: " (itoa done) " exported, "
                              (itoa skipped) " skipped, out of " (itoa total) " attempted."))
              (if (> skipped 0)
                (princ "\nSome poses were skipped (see SKIP lines above) - if that's the jib angle range, tell me the real range from the error messages.")
              )
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
;; N/F/guy flags decided from each config name's letters (see README).

(defun c:EXPORTSWEEP-T3Y ()     (run-config-sweep "T3Y"     nil nil T) )
(defun c:EXPORTSWEEP-T3N ()     (run-config-sweep "T3N"     T   nil nil) )
(defun c:EXPORTSWEEP-T3NY ()    (run-config-sweep "T3NY"    T   nil T) )
(defun c:EXPORTSWEEP-T3NH ()    (run-config-sweep "T3NH"    T   nil nil) )
(defun c:EXPORTSWEEP-T3NYH ()   (run-config-sweep "T3NYH"   T   nil T) )
(defun c:EXPORTSWEEP-T3F ()     (run-config-sweep "T3F"     nil T   nil) )
(defun c:EXPORTSWEEP-T3FH ()    (run-config-sweep "T3FH"    nil T   nil) )
(defun c:EXPORTSWEEP-T3YVEF ()  (run-config-sweep "T3YVEF"  nil T   T) )
(defun c:EXPORTSWEEP-T3YVEFH () (run-config-sweep "T3YVEFH" nil T   T) )

(princ "\nEXPORT_SWEEP_VARIANTS loaded.")
(princ (strcat "\nOutput folder: " *OUTDIR*))
(princ "\nRun ONE config at a time (each is independent):")
(princ "\n  EXPORTSWEEP-T3Y  EXPORTSWEEP-T3N  EXPORTSWEEP-T3NY  EXPORTSWEEP-T3NH")
(princ "\n  EXPORTSWEEP-T3NYH  EXPORTSWEEP-T3F  EXPORTSWEEP-T3FH  EXPORTSWEEP-T3YVEF  EXPORTSWEEP-T3YVEFH")
(princ)
