;; DUMPDYNPROPS - lists every dynamic property on the crane's dynamic
;; block: its name, current value, and (for lookup/list-type properties
;; like a boom config selector) every allowed value it can be set to.
;;
;; READ-ONLY - does not change the drawing at all, nothing to undo, safe
;; to run on your real file.
;;
;; WHY: to sweep other boom configs (T3N, T3Y, attachments, etc.) the
;; same way EXPORTSWEEP already sweeps T3 length x angle, the exact
;; dynamic-property name for the config selector and its exact allowed
;; value strings are needed first - guessing at them risks silently
;; setting the wrong thing or erroring. This finds and prints them.
;;
;; HOW TO RUN:
;;   (load "dump_dynamic_properties.lsp")
;;   DUMPDYNPROPS
;;
;; Prints to the command line AND writes a text file next to your DWG
;; (dyn_props_dump.txt) - copy/paste that file's contents back, or share
;; the file itself, and the actual property name + allowed values can be
;; wired into a proper multi-config EXPORTSWEEP.

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

;; Renders one property's line: name, value, and allowed values if any
;; (lookup/list-type properties only - plain numeric/string properties
;; like boom length or angle don't have a fixed allowed-value list here,
;; their range comes from the block's constraints instead).
(defun describe-prop (prop / pname pval avals avlist line)
  (setq pname (vl-catch-all-apply 'vlax-get (list prop 'PropertyName)))
  (setq pval (vl-catch-all-apply 'vlax-get (list prop 'Value)))
  (if (vl-catch-all-error-p pname) (setq pname "<error reading name>"))
  (if (vl-catch-all-error-p pval) (setq pval "<error reading value>"))

  (setq line (strcat "  " (vl-princ-to-string pname)
                      "  =  " (vl-princ-to-string pval)))

  ;; AllowedValues is nil (not an error) for ordinary properties that
  ;; aren't a lookup/list type (e.g. this crane's boom length/angle,
  ;; which are numeric and constraint-driven, not picked from a fixed
  ;; list) - only force it through variant/safearray conversion when
  ;; something was actually returned.
  (setq avals (vl-catch-all-apply 'vlax-get (list prop 'AllowedValues)))
  (if (and (not (vl-catch-all-error-p avals)) avals)
    (progn
      ;; try unwrapping as a variant-wrapped safearray first; if that
      ;; fails, try treating it as an already-unwrapped safearray
      ;; (different property types can come back either way)
      (setq avlist (vl-catch-all-apply 'vlax-safearray->list
                     (list (vl-catch-all-apply 'vlax-variant-value (list avals)))))
      (if (vl-catch-all-error-p avlist)
        (setq avlist (vl-catch-all-apply 'vlax-safearray->list (list avals)))
      )
      (if (and (not (vl-catch-all-error-p avlist)) avlist)
        (setq line (strcat line "\n      allowed values: " (vl-princ-to-string avlist)))
      )
    )
  )
  line
)

(defun c:DUMPDYNPROPS ( / crane-obj props prop lines outpath f)
  (setq crane-obj (find-crane-obj))
  (if (null crane-obj)
    (princ "\nNo dynamic block found in modelspace. Aborting.")
    (progn
      (setq props (vl-catch-all-apply 'vlax-invoke (list crane-obj 'GetDynamicBlockProperties)))
      (if (vl-catch-all-error-p props)
        (princ (strcat "\nERROR: could not read dynamic properties: "
                        (vl-catch-all-error-message props)))
        (progn
          (setq lines '())
          (princ "\n========================================")
          (princ "\nDynamic properties on the crane block:")
          (princ "\n========================================")
          (foreach prop props
            (setq line (vl-catch-all-apply 'describe-prop (list prop)))
            (if (vl-catch-all-error-p line)
              (setq line (strcat "  <error describing this property: "
                                  (vl-catch-all-error-message line) ">"))
            )
            (setq lines (cons line lines))
            (princ (strcat "\n" line))
          )
          (setq lines (reverse lines))

          ;; also write to a text file so it's easy to copy/paste or share
          (setq outpath (strcat (getenv "USERPROFILE") "/Documents/dyn_props_dump.txt"))
          (setq f (open outpath "w"))
          (if f
            (progn
              (write-line "Dynamic properties on the crane block:" f)
              (write-line "========================================" f)
              (foreach line lines (write-line line f))
              (close f)
              (princ (strcat "\n\nAlso saved to: " outpath))
            )
            (princ "\n\n(could not write the text file, but everything printed above)")
          )
        )
      )
    )
  )
  (princ)
)

(princ "\nDUMPDYNPROPS loaded. Run: DUMPDYNPROPS")
(princ)
