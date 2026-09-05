;; DUMPDYNPROPS - lists every dynamic property on a crane dynamic block
;; YOU CLICK ON: its name, current value, and (for lookup/list-type
;; properties like a boom config selector) every allowed value it can be
;; set to.
;;
;; READ-ONLY - does not change the drawing at all, nothing to undo, safe
;; to run on your real file.
;;
;; WHY IT ASKS YOU TO CLICK: earlier version auto-grabbed "the first
;; dynamic block anywhere in the drawing" (ssget "_X") - fine for a
;; drawing with exactly one dynamic block, wrong the moment there's more
;; than one. On the LTM 1250 file this grabbed a hook/jib-type selector
;; sub-block instead of the boom itself (dumped "Тип крюка"/"Гусек"
;; properties, no boom length/angle anywhere) - confirmed from a real
;; run, not a guess. Clicking the actual boom geometry directly removes
;; the ambiguity entirely.
;;
;; WHY THIS EXISTS AT ALL: to sweep boom configs (T3N, T3Y, attachments,
;; etc.) the same way EXPORTSWEEP sweeps length x angle, the exact
;; dynamic-property name for length/angle/config-selector and its exact
;; allowed value strings are needed first - guessing risks silently
;; setting the wrong thing or erroring.
;;
;; HOW TO RUN:
;;   (load "dump_dynamic_properties.lsp")
;;   DUMPDYNPROPS
;;   -> click directly on the boom (the long telescoping structure
;;      itself, not the hook block, not the carrier/chassis)
;;
;; If the boom is nested inside an outer block (a whole-crane assembly
;; block containing the boom as one of ITS block references), clicking
;; it may select that OUTER block instead, whose own dynamic properties
;; won't include the boom's. If the dump still looks wrong (no length/
;; angle-shaped property), try EXPLODE on a COPY of the outer block
;; first so the boom becomes independently clickable, or zoom in and
;; click precisely on the boom structure rather than near its edge.
;;
;; Prints to the command line AND writes a text file next to your DWG
;; (dyn_props_dump.txt) - copy/paste that file's contents back, or share
;; the file itself, and the actual property name + allowed values can be
;; wired into a proper multi-config EXPORTSWEEP.

;; Asks the person to click the block directly, rather than guessing at
;; "the first dynamic block in the drawing" - see the file header for why
;; that auto-pick approach broke on the LTM 1250 file (grabbed a hook/jib
;; sub-block instead of the boom). Loops on a non-dynamic-block pick so a
;; slightly-off click just re-prompts instead of silently dumping the
;; wrong thing.
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

  ;; AllowedValues: try the compiled vla-get-AllowedValues stub first
  ;; (the documented way to read this on a DynamicBlockReferenceProperty
  ;; COM object), falling back to late-bound vlax-get if that isn't
  ;; available. Nil (not an error) is the normal, expected result for
  ;; ordinary properties that aren't a lookup/list type (e.g. this
  ;; crane's boom length/angle, which are numeric and constraint-driven)
  ;; - only try unwrapping as a variant/safearray when something was
  ;; actually returned, and report WHY if that unwrapping itself fails,
  ;; rather than silently showing nothing either way.
  (setq avals (vl-catch-all-apply 'vla-get-AllowedValues (list prop)))
  (if (vl-catch-all-error-p avals)
    (setq avals (vl-catch-all-apply 'vlax-get (list prop 'AllowedValues)))
  )
  (cond
    ((vl-catch-all-error-p avals)
     (setq line (strcat line "\n      (AllowedValues lookup errored: "
                         (vl-catch-all-error-message avals) ")"))
    )
    ((null avals) nil) ;; genuinely no allowed-values list - fine, say nothing
    (t
     (setq avlist (vl-catch-all-apply 'vlax-safearray->list
                    (list (vl-catch-all-apply 'vlax-variant-value (list avals)))))
     (if (vl-catch-all-error-p avlist)
       (setq avlist (vl-catch-all-apply 'vlax-safearray->list (list avals)))
     )
     (cond
       ((and (not (vl-catch-all-error-p avlist)) avlist)
        (setq line (strcat line "\n      allowed values: " (vl-princ-to-string avlist)))
       )
       ((vl-catch-all-error-p avlist)
        (setq line (strcat line "\n      (got AllowedValues but couldn't unwrap it: "
                            (vl-catch-all-error-message avlist)
                            " | raw type: " (vl-princ-to-string (type avals)) ")"))
       )
     )
    )
  )
  line
)

(defun c:DUMPDYNPROPS ( / crane-obj props prop lines outpath f)
  (setq crane-obj (find-crane-obj))
  (if (null crane-obj)
    (princ "\nCancelled - no block selected.")
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
