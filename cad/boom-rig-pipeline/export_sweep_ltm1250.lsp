;; EXPORT_SWEEP_LTM1250 - batch-exports the LTM 1250's main-boom-only "T"
;; config (boom length x angle), the same decoupled-sweep approach as
;; every other crane in this pipeline. See cad/boom-rig-pipeline/README.md
;; for the full pipeline this feeds into.
;;
;; Property names are THIS crane's own, read directly from a real
;; DUMPDYNPROPS run against the boom block (clicked directly - this
;; crane's file has several dynamic blocks, including separate hook-type
;; and jib selector blocks that are NOT the boom itself):
;;   - "Состав стрелы" (config selector) - set to "T" for boom-only, no
;;     jib/hook attachment. Other allowed values (T+H, TNZK, TVNZK, TS,
;;     TNZF) are jib/attachment configs, same family shape as the LTM
;;     1650/1300 T3/T3F-style variants - not wired up yet, only the
;;     boom-only sweep is built here. Tell me once this one's confirmed
;;     working and I'll build the others the same way.
;;   - "Стрела T" (boom length) - 15 real catalog lengths, 13.05-60.00 m
;;   - "Наклон стрелы T" (boom angle) - continuous/radians, no discrete
;;     list, same convention as every other crane's boom angle property
;;
;; Everything else on this block (ballast, hook type/reeving, jib
;; length, view direction) is left untouched - only the 3 properties
;; above get written, and only for the duration of the sweep.
;;
;; IMPORTANT SAFETY NOTES - READ BEFORE RUNNING:
;;   1. Work on a COPY of the DXF, never your original master file.
;;   2. Do NOT save the drawing after running this. It restores the
;;      block's original property values at the end, but don't rely on
;;      that - just close without saving when you're done.
;;   3. Edit *OUTDIR* below to a real folder if you don't want the
;;      default (created automatically if it doesn't exist).
;;   4. Writes .dwg files - convert the whole output folder to .dxf with
;;      ODA File Converter afterward, same as every other crane here.
;;   5. Run TESTSWEEP first (4 poses) before committing to the full
;;      135-pose EXPORTSWEEP (15 lengths x 9 angles).
;;
;; HOW TO RUN:
;;   (load "export_sweep_ltm1250.lsp")
;;   TESTSWEEP-LTM1250     <- click the boom when prompted, check 4 files
;;   EXPORTSWEEP-LTM1250   <- click the boom again, full 135-pose sweep

;; ===== OUTPUT FOLDER =====
(setq *OUTDIR* (strcat (getenv "USERPROFILE") "/Documents/export_ltm1250/"))
;; =========================================

(setq *PI* 3.14159265358979)

;; All 15 real "Стрела T" catalog lengths (label-for-filename . exact
;; AllowedValues string, including the Cyrillic "м" suffix - vlax-put on
;; a lookup-type property needs an exact string match).
(setq *LENGTHS*
  '(("13.05" . "13.05 м") ("17.37" . "17.37 м") ("21.69" . "21.69 м")
    ("22.44" . "22.44 м") ("26.01" . "26.01 м") ("30.33" . "30.33 м")
    ("34.65" . "34.65 м") ("38.97" . "38.97 м") ("43.29" . "43.29 м")
    ("47.61" . "47.61 м") ("51.92" . "51.92 м") ("54.93" . "54.93 м")
    ("56.24" . "56.24 м") ("59.25" . "59.25 м") ("60.00" . "60.00 м"))
)
(setq *ANGLES-FULL* '(0 10 20 30 40 50 60 70 80))
(setq *ANGLES-TEST* '(0 40))
(setq *LENGTHS-TEST* (list (nth 0 *LENGTHS*) (nth 14 *LENGTHS*)))

;; ---------- helpers ----------

;; Asks the person to click the boom directly, rather than guessing at
;; "the first dynamic block in the drawing" - this file has several
;; (hook-type and jib selector blocks are their own separate dynamic
;; blocks), confirmed from a real DUMPDYNPROPS run that grabbed one of
;; those instead of the boom on the first attempt.
(defun find-crane-obj ( / ent obj isdyn found)
  (setq found nil)
  (while (not found)
    (setq ent (car (entsel "\nClick the boom (the telescoping structure itself): ")))
    (cond
      ((null ent)
       (princ "\nNothing selected - try again, or press Esc to cancel.")
       (setq found 'cancelled)
      )
      (t
       (setq obj (vl-catch-all-apply 'vlax-ename->vla-object (list ent)))
       (cond
         ((vl-catch-all-error-p obj)
          (princ "\nCouldn't read that as an object - click again.")
         )
         (t
          (setq isdyn (vl-catch-all-apply 'vlax-get (list obj 'IsDynamicBlock)))
          (cond
            ((vl-catch-all-error-p isdyn)
             (princ "\nThat's not a block reference at all (picked raw geometry, not an INSERT) - click again, aiming for the block itself.")
            )
            ((not (or (eq isdyn :vlax-true) (and (numberp isdyn) (/= isdyn 0))))
             (princ (strcat "\nThat block (" (vl-catch-all-apply 'vlax-get (list obj 'EffectiveName)) ") isn't a dynamic block - click again."))
            )
            (t (setq found obj))
          )
         )
       )
      )
    )
  )
  (if (eq found 'cancelled) nil found)
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

;; Cancel (not blank-Enter) any leftover pending prompt - see
;; export_sweep_ltm1300.lsp's own comment on why blank-Enter is unsafe
;; here (can silently repeat/corrupt the last wblock/erase).
(defun flush-pending-command ( / n)
  (setq n 0)
  (while (and (> (getvar "CMDACTIVE") 0) (< n 10))
    (command "\x03\x03")
    (setq n (1+ n))
  )
)

;; Same proven engine as export_sweep_ltm1300.lsp's export-current-pose -
;; command called DIRECTLY (not through vl-catch-all-apply 'command),
;; which was the actual root cause of files never landing on disk in an
;; earlier version of this pipeline despite the sweep reporting success.
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

(defun run-ltm1250-sweep (lengths angles / crane-obj cfgprop lenprop angprop
                            orig-cfg orig-len orig-ang total done skipped
                            len-pair angle-deg fname)
  (if (not (vl-file-directory-p *OUTDIR*)) (vl-mkdir *OUTDIR*))
  (setq crane-obj (find-crane-obj))
  (if (null crane-obj)
    (princ "\nCancelled - no block selected.")
    (progn
      (setq cfgprop (get-prop crane-obj "Состав стрелы"))
      (setq lenprop (get-prop crane-obj "Стрела T"))
      (setq angprop (get-prop crane-obj "Наклон стрелы T"))

      (if (or (null cfgprop) (null lenprop) (null angprop))
        (princ "\nERROR: could not find Состав стрелы / Стрела T / Наклон стрелы T on the block you clicked. Did you click the boom itself?")
        (progn
          (setq orig-cfg (vlax-get cfgprop 'Value))
          (setq orig-len (vlax-get lenprop 'Value))
          (setq orig-ang (vlax-get angprop 'Value))

          (if (not (safe-put cfgprop "T" "Состав стрелы"))
            (princ "\nERROR: could not switch Состав стрелы to \"T\". Aborting.")
            (progn
              (vl-catch-all-apply (function (lambda () (command "_.regen"))) nil)
              (setq total (* (length lengths) (length angles)))
              (setq done 0) (setq skipped 0)
              (princ (strcat "\nStarting sweep: " (itoa total) " poses -> " *OUTDIR*))

              (foreach len-pair lengths
                (foreach angle-deg angles
                  (princ (strcat "\n[L=" (car len-pair) "m A=" (itoa angle-deg) "deg]"))
                  (if (and (safe-put lenprop (cdr len-pair) "boom length")
                           (safe-put angprop (* angle-deg (/ *PI* 180.0)) "boom angle"))
                    (progn
                      (vl-catch-all-apply (function (lambda () (command "_.regen"))) nil)
                      (setq fname (strcat *OUTDIR* "pose_L" (car len-pair) "_A" (itoa (fix angle-deg)) ".dwg"))
                      (if (vl-catch-all-apply 'export-current-pose (list crane-obj fname))
                        (setq done (1+ done)) (setq skipped (1+ skipped)))
                    )
                    (setq skipped (1+ skipped))
                  )
                )
              )

              (safe-put cfgprop orig-cfg "restore Состав стрелы")
              (safe-put lenprop orig-len "restore boom length")
              (safe-put angprop orig-ang "restore boom angle")
              (vl-catch-all-apply (function (lambda () (command "_.regen"))) nil)

              (princ "\n----------------------------------------")
              (princ (strcat "\nDone: " (itoa done) " exported, " (itoa skipped)
                              " skipped, out of " (itoa total) " attempted."))
              (princ "\nOriginal property values restored. Do NOT save this drawing.")
              (princ (strcat "\nNext: run ODA File Converter on " *OUTDIR* " to batch-convert DWG -> DXF."))
            )
          )
        )
      )
    )
  )
  (princ)
)

(defun c:TESTSWEEP-LTM1250 ()
  (run-ltm1250-sweep *LENGTHS-TEST* *ANGLES-TEST*)
)

(defun c:EXPORTSWEEP-LTM1250 ()
  (run-ltm1250-sweep *LENGTHS* *ANGLES-FULL*)
)

(princ "\nEXPORT_SWEEP_LTM1250 loaded.")
(princ (strcat "\nOutput folder: " *OUTDIR*))
(princ "\nRun TESTSWEEP-LTM1250 first (4 files, click the boom when prompted),")
(princ "\nthen EXPORTSWEEP-LTM1250 (135 files, click the boom again).")
(princ)
