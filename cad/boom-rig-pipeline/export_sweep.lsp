;; EXPORTSWEEP - batch-exports the crane's main boom (T3 config) at every
;; combination of real boom length x sampled boom angle, using AutoCAD's own
;; dynamic block evaluation (so every exported pose is 100% authentic, not
;; guessed/interpolated).
;;
;; IMPORTANT SAFETY NOTES - READ BEFORE RUNNING:
;;   1. Work on a COPY of the DXF, never your original master file.
;;   2. Do NOT save the drawing after running this. It restores the
;;      boom's original length/angle at the end, but don't rely on that -
;;      just close without saving when you're done.
;;   3. Edit *OUTDIR* below to a real folder on your machine before running
;;      (must already exist, use forward slashes or doubled backslashes).
;;   4. It writes .dwg files (WBLOCK can't write .dxf directly). Afterward,
;;      use the free ODA File Converter (opendesign.com) to batch-convert
;;      the whole output folder from DWG to DXF in one pass.
;;   5. Recommended: first run TESTSWEEP (a 4-file mini version) to confirm
;;      the whole pipeline works before committing to the full 90-file run.
;;
;; HOW TO RUN:
;;   (load "export_sweep.lsp")
;;   TESTSWEEP     <- run this first, check the 4 output files look right
;;   EXPORTSWEEP   <- then the full 90-file sweep

;; ===== OUTPUT FOLDER =====
;; Resolves to Documents\export for whichever Windows user is running
;; AutoCAD (e.g. C:/Users/yourname/Documents/export/). Created
;; automatically if it doesn't already exist - no need to edit this.
(setq *OUTDIR* (strcat (getenv "USERPROFILE") "/Documents/export/"))
;; =========================================

(setq *PI* 3.14159265358979)

;; All 10 real T3 boom lengths: (label-for-filename . exact-AllowedValues-string)
(setq *LENGTHS*
  '(("16.6" . "Стрела 16.6 м")
    ("22.4" . "Стрела 22.4 м")
    ("28.2" . "Стрела 28.2 м")
    ("33.9" . "Стрела 33.9 м")
    ("39.7" . "Стрела 39.7 м")
    ("45.3" . "Стрела 45.3 м")
    ("51.0" . "Стрела 51.0 м")
    ("52.0" . "Стрела 52.0 м")
    ("53.0" . "Стрела 53.0 м")
    ("54.0" . "Стрела 54.0 м")
  )
)

(setq *ANGLES-FULL* '(0 10 20 30 40 50 60 70 80))
(setq *ANGLES-TEST* '(0 40))
(setq *LENGTHS-TEST* (list (nth 0 *LENGTHS*) (nth 9 *LENGTHS*)))

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

;; NOTE: earlier version of this script exploded a copy of the block before
;; exporting. That's wrong for this block - exploding disconnects entities
;; from the BYBLOCK color chain and breaks live fields (the boom-side label
;; text), which is why colors looked washed out and the label showed a
;; placeholder instead of the real designation. Fixed by exporting the
;; reference itself, still nested/un-exploded - WBLOCK pulls in every block
;; definition it needs automatically, and the existing Python/ezdxf pipeline
;; already knows how to resolve BYBLOCK colors and nested inserts correctly.

(defun export-one-pose (crane-obj len-label len-value angle-deg / lenprop angprop
                          rad copyobj copyename ss fname)
  (setq lenprop (get-prop crane-obj "Стрела T3"))
  (setq angprop (get-prop crane-obj "Наклон основной стрелы"))
  (if (and lenprop angprop)
    (progn
      (vlax-put lenprop 'Value len-value)
      (setq rad (* angle-deg (/ *PI* 180.0)))
      (vlax-put angprop 'Value rad)
      (command "_.regen")

      (setq copyobj (vl-catch-all-apply 'vlax-invoke (list crane-obj 'Copy)))
      (if (vl-catch-all-error-p copyobj)
        (princ (strcat "\n  ERROR copying block: " (vl-catch-all-error-message copyobj)))
        (progn
          (setq copyename (vlax-vla-object->ename copyobj))
          (setq fname (strcat *OUTDIR* "pose_L" len-label "_A" (itoa (fix angle-deg)) ".dwg"))
          (setq ss (ssadd))
          (setq ss (ssadd copyename ss))
          ;; delete any pre-existing file at this path first, so -wblock
          ;; never hits an "already exists, overwrite?" prompt mid-command
          ;; (that prompt breaks the whole argument sequence if unanswered).
          (vl-catch-all-apply 'vl-file-delete (list fname))
          ;; select the copy AS-IS (still a block reference, not exploded)
          (command "_.-wblock" fname "" (list 0.0 0.0 0.0) ss "")
          ;; WBLOCK's "Object conversion=Delete" setting removes the copy
          ;; automatically; this is a harmless no-op if that's already true.
          (vl-catch-all-apply 'command (list "_.erase" ss ""))
          (princ (strcat "\n  -> " fname))
        )
      )
    )
    (princ "\n  ERROR: could not find Стрела T3 / Наклон основной стрелы properties")
  )
)

(defun run-sweep (lengths angles / crane-obj lenprop angprop orig-len orig-ang
                    total count len-pair angle-deg)
  (if (not (vl-file-directory-p *OUTDIR*))
    (progn
      (vl-mkdir *OUTDIR*)
      (princ (strcat "\nCreated output folder: " *OUTDIR*))
    )
  )
  (setq crane-obj (find-crane-obj))
  (if (null crane-obj)
    (princ "\nNo dynamic block found in modelspace. Aborting.")
    (progn
      ;; Lock to main-boom-only T3 config first.
      (setq lenprop (get-prop crane-obj "Стрела T3"))
      (setq angprop (get-prop crane-obj "Наклон основной стрелы"))
      (setq orig-len (if lenprop (vlax-get lenprop 'Value) nil))
      (setq orig-ang (if angprop (vlax-get angprop 'Value) nil))

      (setq total (* (length lengths) (length angles)))
      (setq count 0)
      (princ (strcat "\nStarting sweep: " (itoa total) " poses -> " *OUTDIR*))

      (foreach len-pair lengths
        (foreach angle-deg angles
          (setq count (1+ count))
          (princ (strcat "\n[" (itoa count) "/" (itoa total) "] L=" (car len-pair) "m A=" (itoa angle-deg) "deg"))
          (vl-catch-all-apply 'export-one-pose
            (list crane-obj (car len-pair) (cdr len-pair) angle-deg))
        )
      )

      ;; restore original values
      (if (and lenprop orig-len) (vlax-put lenprop 'Value orig-len))
      (if (and angprop orig-ang) (vlax-put angprop 'Value orig-ang))
      (command "_.regen")

      (princ "\n----------------------------------------")
      (princ (strcat "\nDone. " (itoa total) " poses attempted. Original angle/length restored."))
      (princ "\nDo NOT save this drawing. Close without saving.")
      (princ (strcat "\nNext: run ODA File Converter on " *OUTDIR* " to batch-convert DWG -> DXF."))
    )
  )
  (princ)
)

(defun c:TESTSWEEP ()
  (run-sweep *LENGTHS-TEST* *ANGLES-TEST*)
)

(defun c:EXPORTSWEEP ()
  (run-sweep *LENGTHS* *ANGLES-FULL*)
)

(princ "\nEXPORTSWEEP loaded.")
(princ (strcat "\nOutput folder is currently set to: " *OUTDIR*))
(princ "\nEdit *OUTDIR* in the file if that's wrong, then reload.")
(princ "\nRun TESTSWEEP first (4 files), then EXPORTSWEEP (90 files).")
(princ)
