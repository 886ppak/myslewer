;; EXPORT_SWEEP_LTM1130 - batch-exports the LTM 1130-5.1's main-boom-only
;; "T" config (boom length x angle), same decoupled-sweep approach as
;; every other crane in this pipeline. See cad/boom-rig-pipeline/README.md.
;;
;; Property names are THIS crane's own, read directly from a real
;; DUMPDYNPROPS run against the boom block (click-to-select, per
;; methodology.txt 163) - a fourth distinct naming convention among the
;; cranes done so far, none guessable from another's:
;;   - "Тип стрелы" (config selector - "boom TYPE", not "Состав стрелы"/
;;     "Состав" like every other crane so far) - set to "T" for boom-only.
;;     Other allowed values (T+R, TK 2.9 м, TK, TVK) are jib/attachment
;;     configs, not wired up yet.
;;   - "Visibility1" - a second property mirroring the same allowed-value
;;     list, same "set both defensively" treatment as every other crane's
;;     twin property (Состав/видимость elsewhere).
;;   - "Основная стрела" (boom length - "MAIN boom", matches the LTM
;;     1300's own property name exactly, coincidentally - not "Стрела T"
;;     like the other three cranes) - 18 real catalog lengths, 12.7-60.0
;;     m, bare "12.7 м" format (number + space + м, no prefix).
;;   - "Наклон стрелы" (boom angle - no "T" suffix, unlike every other
;;     crane's "Наклон [основной/стрелы] T") - continuous/radians, no
;;     discrete list.
;;
;; Everything else on this block (winch, hook type/reeving, jib length,
;; jib angle) is left untouched.
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
;;      162-pose EXPORTSWEEP (18 lengths x 9 angles).
;;
;; HOW TO RUN:
;;   (load "export_sweep_ltm1130.lsp")
;;   TESTSWEEP-LTM1130     <- click the boom when prompted, check 4 files
;;   EXPORTSWEEP-LTM1130   <- click the boom again, full 162-pose sweep

;; ===== OUTPUT FOLDER =====
(setq *OUTDIR* (strcat (getenv "USERPROFILE") "/Documents/export_ltm1130/"))
;; =========================================

(setq *PI* 3.14159265358979)

;; All 18 real "Основная стрела" catalog lengths (label-for-filename .
;; exact AllowedValues string).
(setq *LENGTHS*
  '(("12.7" . "12.7 м") ("17.0" . "17.0 м") ("21.4" . "21.4 м") ("22.1" . "22.1 м")
    ("25.7" . "25.7 м") ("30.1" . "30.1 м") ("31.6" . "31.6 м") ("34.4" . "34.4 м")
    ("38.8" . "38.8 м") ("41.1" . "41.1 м") ("43.1" . "43.1 м") ("47.5" . "47.5 м")
    ("50.5" . "50.5 м") ("51.9" . "51.9 м") ("54.9" . "54.9 м") ("56.2" . "56.2 м")
    ("59.2" . "59.2 м") ("60.0" . "60.0 м"))
)
(setq *ANGLES-FULL* '(0 10 20 30 40 50 60 70 80))
(setq *ANGLES-TEST* '(0 40))
(setq *LENGTHS-TEST* (list (nth 0 *LENGTHS*) (nth 17 *LENGTHS*)))

;; ---------- helpers ----------

;; Asks the person to click the boom directly, rather than guessing at
;; "the first dynamic block in the drawing" - see methodology.txt 163 for
;; why that auto-pick approach broke on a file with multiple dynamic
;; blocks (hook-type/jib selectors are their own separate blocks, not
;; properties nested in the boom's own).
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

(defun run-ltm1130-sweep (lengths angles / crane-obj cfgprop cfgprop2 lenprop angprop
                            orig-cfg orig-cfg2 orig-len orig-ang total done skipped
                            len-pair angle-deg fname)
  (if (not (vl-file-directory-p *OUTDIR*)) (vl-mkdir *OUTDIR*))
  (setq crane-obj (find-crane-obj))
  (if (null crane-obj)
    (princ "\nCancelled - no block selected.")
    (progn
      (setq cfgprop (get-prop crane-obj "Тип стрелы"))
      (setq cfgprop2 (get-prop crane-obj "Visibility1"))
      (setq lenprop (get-prop crane-obj "Основная стрела"))
      (setq angprop (get-prop crane-obj "Наклон стрелы"))

      (if (or (null cfgprop) (null lenprop) (null angprop))
        (princ "\nERROR: could not find Тип стрелы / Основная стрела / Наклон стрелы on the block you clicked. Did you click the boom itself?")
        (progn
          (setq orig-cfg (vlax-get cfgprop 'Value))
          (setq orig-cfg2 (if cfgprop2 (vlax-get cfgprop2 'Value) nil))
          (setq orig-len (vlax-get lenprop 'Value))
          (setq orig-ang (vlax-get angprop 'Value))

          (if (not (safe-put cfgprop "T" "Тип стрелы"))
            (princ "\nERROR: could not switch Тип стрелы to \"T\". Aborting.")
            (progn
              (if cfgprop2 (safe-put cfgprop2 "T" "Visibility1"))
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

              (safe-put cfgprop orig-cfg "restore Тип стрелы")
              (if (and cfgprop2 orig-cfg2) (safe-put cfgprop2 orig-cfg2 "restore Visibility1"))
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

(defun c:TESTSWEEP-LTM1130 ()
  (run-ltm1130-sweep *LENGTHS-TEST* *ANGLES-TEST*)
)

(defun c:EXPORTSWEEP-LTM1130 ()
  (run-ltm1130-sweep *LENGTHS* *ANGLES-FULL*)
)

(princ "\nEXPORT_SWEEP_LTM1130 loaded.")
(princ (strcat "\nOutput folder: " *OUTDIR*))
(princ "\nRun TESTSWEEP-LTM1130 first (4 files, click the boom when prompted),")
(princ "\nthen EXPORTSWEEP-LTM1130 (162 files, click the boom again).")
(princ)
