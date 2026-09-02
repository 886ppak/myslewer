;; EXPORT_SWEEP_JIB_FULL - the jib N/F configs currently only have real
;; captured geometry for jib (length x angle) at ONE frozen main-boom
;; length+angle (see export_sweep_variants.lsp's pass 2/2b). The app
;; works around the missing main-boom ANGLE freedom with a runtime rigid
;; rotation (verified mathematically exact - a boom is a rigid body, so
;; rotating the whole frozen boom+jib assembly around the boom's own
;; pivot is identical to having captured it at that angle directly).
;; There is NO equivalent shortcut for main-boom LENGTH - a telescoping
;; boom's real shape differs section-by-section at every length, so that
;; axis needs real captured data, same as it does everywhere else in
;; this pipeline.
;;
;; This script captures BOTH: for each of the 10 real main-boom lengths
;; AND each of the 9 real main-boom angles, sweep jib (length x angle)
;; fully. That's the "most complete" option - it also gives ground-truth
;; data at every boom angle, not just the rotation-trick's math, at the
;; cost of a MUCH bigger export than anything run so far in this
;; pipeline. See the pose-count math below before running anything.
;;
;; The H variants (T3NH, T3NYH, T3FH, T3YVEFH) are essentially the same
;; geometry as their non-H counterpart (T3N, T3NY, T3F, T3YVEF) - dropped
;; entirely from this script rather than doubling an already enormous
;; export for configs that wouldn't add real coverage. Only run this for
;; T3N, T3NY, T3F, T3YVEF; if the H variants ever do need their own real
;; data, copy one of the confirm-and-run-full lines near the bottom.
;;
;; ############################################################
;; ##  POSE COUNT - READ THIS BEFORE RUNNING ANYTHING BELOW  ##
;; ############################################################
;;   For ONE config: (boom lengths) x (boom angles) x (jib lengths) x (jib angles)
;;     Jib N configs (T3N, T3NY):  10 x 9 x 21 x 9 = 17,010 poses each
;;     Jib F configs (T3F, T3YVEF): 10 x 9 x 17 x 9 = 13,770 poses each
;;   All 4 jib configs, fully: (2 x 17,010) + (2 x 13,770) = 61,560 poses.
;;   At roughly 2-3 seconds per pose (wblock + regen overhead, consistent
;;   with the earlier sweeps), that's 35-50+ HOURS of AutoCAD run time
;;   for everything - not realistic in one sitting, or several.
;;
;;   *BOOM-ANGLES-SWEEP* and *LENGTHS* below are edit-before-you-run
;;   lists, same as every other script in this pipeline - trim them
;;   first if the full count is too much. Two practical ways to cut it
;;   down a lot without losing much real value:
;;     - Drop *BOOM-ANGLES-SWEEP* to a handful spread across the range
;;       (e.g. 0/40/80) instead of all 9 - this is really a spot-check
;;       against the rotation trick, not a real gap, so it doesn't need
;;       dense coverage. Cuts the count to ~1/3.
;;     - Run ONE boom length at a time (RUN-ONE-LENGTH prompts for
;;       which) instead of all 10 in one sitting - lets you stop between
;;       lengths and pick up later without losing progress, and lets you
;;       ship boom lengths as they finish instead of waiting for all 10.
;;
;; Guy angle (T3NY/T3YVEF) is held at its reference value
;; throughout, same as the original decoupled sweep - adding a 3-way guy
;; axis on top of this would triple an already enormous export for very
;; little real value (guy angle doesn't interact with boom/jib geometry).
;;
;; Standalone from the other scripts here - load on its own.
;;
;; SAFETY NOTES (same as export_sweep_variants.lsp):
;;   1. Work on a COPY of the DXF, never your original master file.
;;   2. Do NOT save the drawing after running this.
;;   3. Edit *OUTDIR* below to a real folder before running.
;;   4. Writes .dwg files - convert the whole output folder to .dxf with
;;      ODA File Converter afterward.
;;   5. Jib angle range (*JIB-ANGLES*) is the same 0-40 guess as before -
;;      anything AutoCAD rejects is skipped automatically and logged.
;;
;; HOW TO RUN:
;;   (load "export_sweep_jib_full.lsp")
;;   RUN-ONE-LENGTH     -> prompts for config name + which boom length
;;                          index (0-9) to sweep fully (all 9 angles x
;;                          full jib grid) - the resumable, chunked way.
;;   EXPORTSWEEP-T3N-FULL, EXPORTSWEEP-T3NY-FULL,
;;   EXPORTSWEEP-T3F-FULL, EXPORTSWEEP-T3YVEF-FULL
;;                       -> sweeps ALL 10 boom lengths for ONE config in
;;                          one sitting (prints the pose count and asks
;;                          you to type YES before starting).
;;   EXPORTSWEEP-ALL-JIB-FULL
;;                       -> commits to ALL 4 configs, all 10 boom lengths
;;                          each, back-to-back with ONE confirmation up
;;                          front (~61,500 poses, ~35-50 hours - this is
;;                          the "just run everything now" command).

;; ===== OUTPUT FOLDER =====
(setq *OUTDIR* (strcat (getenv "USERPROFILE") "/Documents/export/"))
;; =========================================

(setq *PI* 3.14159265358979)

;; All 10 real T3 boom lengths (same as export_sweep.lsp /
;; export_sweep_variants.lsp)
(setq *LENGTHS*
  '(("16.6" . "Стрела 16.6 м") ("22.4" . "Стрела 22.4 м") ("28.2" . "Стрела 28.2 м")
    ("33.9" . "Стрела 33.9 м") ("39.7" . "Стрела 39.7 м") ("45.3" . "Стрела 45.3 м")
    ("51.0" . "Стрела 51.0 м") ("52.0" . "Стрела 52.0 м") ("53.0" . "Стрела 53.0 м")
    ("54.0" . "Стрела 54.0 м"))
)

;; EDIT THIS to trade off completeness vs. runtime - see the pose-count
;; note at the top. Full catalog is 0-80 in 10deg steps; trimming to
;; e.g. '(0 40 80) cuts the whole export to ~1/3 and is really all this
;; axis needs (it's a spot-check against the rotation trick, not a real
;; data gap the way boom length is).
(setq *BOOM-ANGLES-SWEEP* '(0 10 20 30 40 50 60 70 80))

;; Reference value held fixed for whichever of jib/guy this pass isn't
;; sweeping (same convention as export_sweep_variants.lsp).
(setq *REF-JIB-ANGLE* 0)

(setq *JIB-N-LENGTHS*
  '(("21.0" . "Гусек 21.0 м") ("24.5" . "Гусек 24.5 м") ("28.0" . "Гусек 28.0 м")
    ("31.5" . "Гусек 31.5 м") ("35.0" . "Гусек 35.0 м") ("38.5" . "Гусек 38.5 м")
    ("42.0" . "Гусек 42.0 м") ("45.5" . "Гусек 45.5 м") ("49.0" . "Гусек 49.0 м")
    ("52.5" . "Гусек 52.5 м") ("56.0" . "Гусек 56.0 м") ("59.5" . "Гусек 59.5 м")
    ("63.0" . "Гусек 63.0 м") ("66.5" . "Гусек 66.5 м") ("70.0" . "Гусек 70.0 м")
    ("73.5" . "Гусек 73.5 м") ("77.0" . "Гусек 77.0 м") ("80.5" . "Гусек 80.5 м")
    ("84.0" . "Гусек 84.0 м") ("87.5" . "Гусек 87.5 м") ("91.0" . "Гусек 91.0 м"))
)
(setq *JIB-F-LENGTHS*
  '(("6.0" . "Гусек 6.0 м") ("9.5" . "Гусек 9.5 м") ("13.0" . "Гусек 13.0 м")
    ("16.5" . "Гусек 16.5 м") ("20.0" . "Гусек 20.0 м") ("23.5" . "Гусек 23.5 м")
    ("27.0" . "Гусек 27.0 м") ("30.5" . "Гусек 30.5 м") ("34.0" . "Гусек 34.0 м")
    ("37.5" . "Гусек 37.5 м") ("41.0" . "Гусек 41.0 м") ("44.5" . "Гусек 44.5 м")
    ("48.0" . "Гусек 48.0 м") ("51.5" . "Гусек 51.5 м") ("55.0" . "Гусек 55.0 м")
    ("58.5" . "Гусек 58.5 м") ("62.0" . "Гусек 62.0 м"))
)
(setq *JIB-ANGLES* '(0 5 10 15 20 25 30 35 40))
(setq *GUY-ANGLES* '(("30" . "30 град.") ("45" . "45 град.") ("60" . "60 град.")))

;; ---------- helpers (identical to export_sweep_variants.lsp) ----------

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
  (setq r (vl-catch-all-apply 'vlax-put (list prop 'Value val)))
  (if (vl-catch-all-error-p r)
    (progn
      (princ (strcat "\n    SKIP (" label "): " (vl-catch-all-error-message r)))
      nil
    )
    T
  )
)

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
      (command "_.-wblock" fname "" (list 0.0 0.0 0.0) ss "")
      (flush-pending-command)
      (command "_.erase" ss "")
      (flush-pending-command)
      (setq ok (findfile fname))
      (if ok
        (princ (strcat "\n    -> " fname))
        (princ (strcat "\n    FAILED (no file written): " fname))
      )
      (if ok T nil)
    )
  )
)

(defun write-test-ok ( / f ok)
  (if (not (vl-file-directory-p *OUTDIR*)) (vl-mkdir *OUTDIR*))
  (setq ok nil)
  (if (vl-file-directory-p *OUTDIR*)
    (progn
      (setq *WTF* (strcat *OUTDIR* "write_test.txt"))
      (setq f (open *WTF* "w"))
      (if f
        (progn
          (write-line "test" f) (close f)
          (setq ok (findfile *WTF*))
          (if ok (vl-file-delete *WTF*))
        )
      )
    )
  )
  ok
)

;; ---------- the full sweep worker ----------
;; config-name: e.g. "T3N". jib-kind: 'N or 'F. has-guy: T/nil.
;; length-indices: list of 0-based indices into *LENGTHS* to sweep this
;; run (lets RUN-ONE-LENGTH do a single length; the FULL commands pass
;; every index).
(defun run-full-jib-sweep (config-name jib-kind has-guy length-indices
                            / crane-obj visprop lenprop angprop jprop japrop gprop
                              orig-vis orig-len orig-ang orig-j orig-ja orig-guy
                              jib-lengths total done skipped
                              li len-pair angle-deg jlen-pair fname)
  (setq jib-lengths (if (eq jib-kind 'N) *JIB-N-LENGTHS* *JIB-F-LENGTHS*))

  (if (not (write-test-ok))
    (princ (strcat "\n\n*** ABORTING: " *OUTDIR* " is not writable. Check the path. ***"))
    (progn
      (setq crane-obj (find-crane-obj))
      (if (null crane-obj)
        (princ "\nNo dynamic block found in modelspace. Aborting.")
        (progn
          (setq visprop (get-prop crane-obj "Visibility1"))
          (setq lenprop (get-prop crane-obj "Стрела T3"))
          (setq angprop (get-prop crane-obj "Наклон основной стрелы"))
          (setq jprop   (get-prop crane-obj (if (eq jib-kind 'N) "Гусек N" "Гусек F")))
          (setq japrop  (get-prop crane-obj "Наклон гуська"))
          (setq gprop   (get-prop crane-obj "Расчалы"))

          (if (null visprop)
            (princ "\nERROR: could not find Visibility1 property. Aborting.")
            (progn
              (setq orig-vis (vlax-get visprop 'Value))
              (setq orig-len (if lenprop (vlax-get lenprop 'Value) nil))
              (setq orig-ang (if angprop (vlax-get angprop 'Value) nil))
              (setq orig-j   (if jprop (vlax-get jprop 'Value) nil))
              (setq orig-ja  (if japrop (vlax-get japrop 'Value) nil))
              (setq orig-guy (if gprop (vlax-get gprop 'Value) nil))

              (if (not (safe-put visprop config-name "Visibility1"))
                (princ (strcat "\nERROR: could not switch to " config-name ". Aborting."))
                (progn
                  (vl-catch-all-apply (function (lambda () (command "_.regen"))) nil)
                  (if has-guy (safe-put gprop (cdr (nth 0 *GUY-ANGLES*)) "ref guy angle"))

                  (setq total 0) (setq done 0) (setq skipped 0)
                  (princ (strcat "\n=== " config-name ": full boom(L x A) x jib(L x A) sweep ==="))
                  (princ (strcat "\n    boom lengths this run: " (itoa (length length-indices))
                                  " / angles: " (itoa (length *BOOM-ANGLES-SWEEP*))
                                  " / jib lengths: " (itoa (length jib-lengths))
                                  " / jib angles: " (itoa (length *JIB-ANGLES*))))
                  (princ (strcat "\n    max poses this run: "
                                  (itoa (* (length length-indices) (length *BOOM-ANGLES-SWEEP*)
                                            (length jib-lengths) (length *JIB-ANGLES*)))))

                  (foreach li length-indices
                    (setq len-pair (nth li *LENGTHS*))
                    (foreach angle-deg *BOOM-ANGLES-SWEEP*
                      (if (and (safe-put lenprop (cdr len-pair) "main length")
                               (safe-put angprop (* angle-deg (/ *PI* 180.0)) "main angle"))
                        (progn
                          (vl-catch-all-apply (function (lambda () (command "_.regen"))) nil)
                          (foreach jlen-pair jib-lengths
                            (foreach jangle-deg *JIB-ANGLES*
                              (setq total (1+ total))
                              (if (and (safe-put jprop (cdr jlen-pair) "jib length")
                                       (safe-put japrop (* jangle-deg (/ *PI* 180.0)) "jib angle"))
                                (progn
                                  (vl-catch-all-apply (function (lambda () (command "_.regen"))) nil)
                                  (setq fname (strcat *OUTDIR* "pose_" config-name
                                                       "_L" (car len-pair) "_A" (itoa (fix angle-deg))
                                                       "_JL" (car jlen-pair) "_JA" (itoa (fix jangle-deg))
                                                       ".dwg"))
                                  (if (vl-catch-all-apply 'export-current-pose (list crane-obj fname))
                                    (setq done (1+ done)) (setq skipped (1+ skipped))
                                  )
                                )
                                (setq skipped (1+ skipped))
                              )
                            )
                          )
                        )
                        (setq skipped (+ skipped (* (length jib-lengths) (length *JIB-ANGLES*))))
                      )
                    )
                    (princ (strcat "\n  -- boom length " (car len-pair) " done ("
                                    (itoa done) "/" (itoa total) " so far) --"))
                  )

                  (safe-put visprop orig-vis "restore Visibility1")
                  (if (and lenprop orig-len) (safe-put lenprop orig-len "restore main length"))
                  (if (and angprop orig-ang) (safe-put angprop orig-ang "restore main angle"))
                  (if (and jprop orig-j) (safe-put jprop orig-j "restore jib"))
                  (if (and japrop orig-ja) (safe-put japrop orig-ja "restore jib angle"))
                  (if (and gprop orig-guy) (safe-put gprop orig-guy "restore guy angle"))
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
    )
  )
  (princ)
)

;; ---------- confirmation wrapper for a full (all 10 lengths) run ----------
(defun confirm-and-run-full (config-name jib-kind has-guy / jib-lengths est ans)
  (setq jib-lengths (if (eq jib-kind 'N) *JIB-N-LENGTHS* *JIB-F-LENGTHS*))
  (setq est (* (length *LENGTHS*) (length *BOOM-ANGLES-SWEEP*)
                (length jib-lengths) (length *JIB-ANGLES*)))
  (princ (strcat "\n" config-name ": this run will attempt up to " (itoa est) " poses "
                  "(all " (itoa (length *LENGTHS*)) " boom lengths x "
                  (itoa (length *BOOM-ANGLES-SWEEP*)) " boom angles x "
                  (itoa (length jib-lengths)) " jib lengths x "
                  (itoa (length *JIB-ANGLES*)) " jib angles)."))
  (princ "\nAt ~2-3 sec/pose that's roughly ")
  (princ (rtos (/ (* est 2.5) 3600.0) 2 1))
  (princ " hours. Type YES (all caps) to proceed, anything else to cancel: ")
  (setq ans (getstring))
  (if (= ans "YES")
    (run-full-jib-sweep config-name jib-kind has-guy
      (append '(0 1 2 3 4 5 6 7 8 9) nil)) ;; all 10 length indices
    (princ "\nCancelled - nothing exported.")
  )
  (princ)
)

(defun c:EXPORTSWEEP-T3N-FULL ()     (confirm-and-run-full "T3N"     'N nil) )
(defun c:EXPORTSWEEP-T3NY-FULL ()    (confirm-and-run-full "T3NY"    'N T) )
(defun c:EXPORTSWEEP-T3F-FULL ()     (confirm-and-run-full "T3F"     'F nil) )
(defun c:EXPORTSWEEP-T3YVEF-FULL ()  (confirm-and-run-full "T3YVEF"  'F T) )

;; ---------- all 4 remaining jib configs, one sitting, one confirmation ----------
;; Same YES safeguard as confirm-and-run-full but totalled across all 4
;; configs up front, then runs each in sequence with no further prompts -
;; this is the "commit to everything now" command. Still writes and
;; verifies (findfile) every file as it goes and restores the drawing's
;; original property values after each config, same as every other path
;; through this script - an interruption partway through (Escape) just
;; means the LATER configs weren't attempted, nothing already written is
;; at risk.
(defun c:EXPORTSWEEP-ALL-JIB-FULL ( / est-n est-f total ans all-lengths)
  (setq all-lengths (append '(0 1 2 3 4 5 6 7 8 9) nil))
  (setq est-n (* (length *LENGTHS*) (length *BOOM-ANGLES-SWEEP*)
                  (length *JIB-N-LENGTHS*) (length *JIB-ANGLES*)))
  (setq est-f (* (length *LENGTHS*) (length *BOOM-ANGLES-SWEEP*)
                  (length *JIB-F-LENGTHS*) (length *JIB-ANGLES*)))
  (setq total (+ (* 2 est-n) (* 2 est-f))) ;; T3N+T3NY, T3F+T3YVEF
  (princ (strcat "\nALL 4 configs (T3N, T3NY, T3F, T3YVEF), all 10 boom lengths each: "
                  "up to " (itoa total) " poses total."))
  (princ "\nAt ~2-3 sec/pose that's roughly ")
  (princ (rtos (/ (* total 2.5) 3600.0) 2 1))
  (princ " hours, run back-to-back with no further prompts once started.")
  (princ "\nType YES (all caps) to proceed, anything else to cancel: ")
  (setq ans (getstring))
  (if (/= ans "YES")
    (princ "\nCancelled - nothing exported.")
    (progn
      (princ "\n\n########## STARTING: T3N ##########")
      (run-full-jib-sweep "T3N" 'N nil all-lengths)
      (princ "\n\n########## STARTING: T3NY ##########")
      (run-full-jib-sweep "T3NY" 'N T all-lengths)
      (princ "\n\n########## STARTING: T3F ##########")
      (run-full-jib-sweep "T3F" 'F nil all-lengths)
      (princ "\n\n########## STARTING: T3YVEF ##########")
      (run-full-jib-sweep "T3YVEF" 'F T all-lengths)
      (princ "\n\n########## ALL 4 CONFIGS DONE ##########")
    )
  )
  (princ)
)

;; ---------- chunked, resumable single-length runner ----------
(defun c:RUN-ONE-LENGTH ( / cfg kind-str kind has-guy idx-str idx len-pair)
  (princ "\nConfig name (T3N, T3F, T3NY, or T3YVEF - H variants dropped, see top of file): ")
  (setq cfg (strcase (getstring)))
  (setq kind (cond ((member cfg '("T3N" "T3NY")) 'N)
                    ((member cfg '("T3F" "T3YVEF")) 'F)
                    (T nil)))
  (setq has-guy (member cfg '("T3NY" "T3YVEF")))
  (if (null kind)
    (princ (strcat "\nUnrecognized config: " cfg ". Aborting."))
    (progn
      (princ "\nBoom length index (0=16.6 .. 9=54.0): ")
      (setq idx-str (getstring))
      (setq idx (atoi idx-str))
      (setq len-pair (nth idx *LENGTHS*))
      (if (null len-pair)
        (princ "\nBad index. Aborting.")
        (progn
          (princ (strcat "\nRunning " cfg " for boom length " (car len-pair)
                          " only (" (itoa (length *BOOM-ANGLES-SWEEP*)) " angles x full jib grid)."))
          (run-full-jib-sweep cfg kind has-guy (list idx))
        )
      )
    )
  )
  (princ)
)

(princ "\nEXPORT_SWEEP_JIB_FULL loaded.")
(princ (strcat "\nOutput folder: " *OUTDIR*))
(princ "\nResumable, one boom length at a time (recommended):")
(princ "\n  RUN-ONE-LENGTH")
(princ "\nOr all 10 boom lengths for one config in one sitting (asks to confirm first):")
(princ "\n  EXPORTSWEEP-T3N-FULL  EXPORTSWEEP-T3NY-FULL  EXPORTSWEEP-T3F-FULL  EXPORTSWEEP-T3YVEF-FULL")
(princ "\nOr commit to all 4 configs right now, one confirmation, back-to-back:")
(princ "\n  EXPORTSWEEP-ALL-JIB-FULL")
(princ "\n(H variants dropped - see top of file)")
(princ "\nEdit *BOOM-ANGLES-SWEEP* near the top to trade off completeness vs. runtime first.")
(princ)
