;; Example mappings:

(defun my/example-bindings ()
  (progn

    (global-set-key (kbd "C-c g g") '(lambda () (interactive) (shell-command "jj show --git")))
    
    ;; Split selected portions of the
    ;; Use this inside "jj show --git" output because it needs a unified
    ;; diff and a commit-ID or preferrably change-ID).
    (global-set-key (kbd "C-c g i") 'my/jj-split)

    ;; Apply (selected portions of the diff)
    (global-set-key (kbd "C-c g a") '(lambda () (interactive) (my/git-apply)))
    ;; Apply, tolerating context mismatch.
    (global-set-key (kbd "C-c g 3") '(lambda () (interactive) (my/git-apply "--3way")))
    ;; Revert
    (global-set-key (kbd "C-c g x") '(lambda () (interactive) (my/git-apply "--reverse")))

    ;; The following are useful when working without jj
    ;; Stage
    (global-set-key (kbd "C-c g s") '(lambda () (interactive) (my/git-apply "--cached")))
    ;; Unstage
    (global-set-key (kbd "C-c g u") '(lambda () (interactive) (my/git-apply "--reverse" "--cached")))
    ;; Revert and unstage
    (global-set-key (kbd "C-c g X") '(lambda () (interactive) (my/git-apply "--reverse" "--index")))
    ))

;; TODO
;; - documentation
;; - move to an actual plugin
;; - make it more idiomatic (I haven't used Emacs in 6 years)

(defvar my/--parent-directory
  (file-name-directory (or load-file-name (buffer-file-name))))

(defun my/patch (&rest patch-cmd-argv)
"
TODO:
- support multiple selections
"
  (interactive)
  (progn
    (let*
        ;; from Claude:
        ;; Prompts: consider jj.el. Change my/patch such that if the region
        ;; contains no newline, select the entire hunk (starting at
        ;; the line starting with @@) before doing anything else.
        ;;
        ;; 1. it should also work if there is no region
        ;; 2. make sure it works if the current hunk is the last hunk in the file
        ((region-contains-newline
          (and (region-active-p)
               (string-match-p "\n" (buffer-substring (region-beginning) (region-end)))))
         (min-line
          (line-number-at-pos
           (if
               (region-active-p)
               (region-beginning)
             (point))))
         (max-line
          (line-number-at-pos
           (if
               (region-active-p)
               (region-end)
             (point)))))
      ;; adapted from Claude:
      ;; Prompt (on top of the above one;; ): also, if no region is
      ;; active, ;; and the cursor is on a diff header line (starting
      ;; with ;; "diff"), then select the entire file-diff, i.e. from
      ;; the ;; "diff" line to the next one or the end of file
      (when (not (region-active-p))
        (save-excursion
          ;; Check if cursor is on a diff header line
          (beginning-of-line)
          (if (looking-at "^diff ")
              ;; Select entire file-diff from current line to next diff or end of buffer
              (progn
                (setq min-line (line-number-at-pos))
                (forward-line 1)
                (if (re-search-forward "^diff " nil t)
                    ;; Found next diff, go to line before it
                    (progn
                      (forward-line -1)
                      (end-of-line)
                      (setq max-line (line-number-at-pos)))
                  ;; No next diff found, go to end of buffer
                  (goto-char (point-max))
                  (setq max-line (line-number-at-pos))))
            ;; Not on diff header, find current hunk (line starting with @@)
            (when (re-search-backward "^@@" nil t)
              (setq min-line (line-number-at-pos))
              ;; Find end of current hunk (next @@ line or end of buffer)
              (forward-line 1)
              (if (re-search-forward "^@@" nil t)
                  ;; Found next hunk, go to line before it
                  (progn
                    (forward-line -1)
                    (end-of-line)
                    (setq max-line (line-number-at-pos)))
                ;; No next hunk found, go to end of buffer
                (goto-char (point-max))
                (setq max-line (line-number-at-pos)))))))
      (let*
          ((start-pos
            (save-excursion
              (goto-char (if (region-active-p) (region-beginning) (point)))
              (if (re-search-backward "^diff " nil t)
                  (point)
                1)))
           (line-offset (- (line-number-at-pos start-pos) 1))
           (cmd
            (format
             ;; NOTE: we redirect normal output to stderr because
             ;; stdout is used to pipe back the remaining diff.
             "%s/rc/tools/patch-range.pl -print-remaining-diff %d %d %s '>&2'"
             my/--parent-directory
             (- min-line line-offset)
             (- max-line line-offset)
             (string-join
              (mapcar
               (lambda (arg)
                 (shell-quote-argument arg 'POSIX))
               patch-cmd-argv)
              " ")
             ))
           (lines-before (count-lines (point-min) (point-max)))
           )
        (if
            (not
             (eq
              0
              (shell-command-on-region
               start-pos
               (point-max)
               cmd
               nil
               'REPLACE
               "*patch-stderr*")))
            nil
          (progn
            ;; from Claude:
            ;; Prompt: [...] actually keep the goto-line but subtract
            ;; from the target line number the net number of removed
            ;; lines. you can assume that it's non-negative
            (let* ((lines-after (count-lines (point-min) (point-max)))
                   (net-removed-lines (- lines-before lines-after))
                   (adjusted-max-line (- max-line net-removed-lines)))
              (goto-line adjusted-max-line))
            t
            ))))))

(defun my/git-apply (&rest args)
  (interactive)
  (apply
   'my/patch
   (append (list "git" "apply")
           args)))

(defun my/jj-split ()
  "
TODO:
- forward arguments (but ignore selections when passed a fileset)
"
  (interactive)
  (let*
      ((revision
        (save-mark-and-excursion
          (if
              (search-backward-regexp
               "^\\(?:commit\\|Change ID:\\) \\(\\w+\\)$"
               nil
               'NOERROR)
              (match-string 1)
            "@" ;; assume we're splitting the working copy commit
            )))
       (state-file
        (car
         (process-lines
          "mktemp"
          (format
           "%s/jj.el-split.XXXXXXXX"
           (or
            (getenv "TMPDIR")
            "/tmp")))))
       (is-description-empty
        (if
            (process-lines
             "jj" "log" "--no-graph" "--ignore-working-copy"
             "-r" revision "-T" "description")
            "false"
          "true"))
       ;; Don't prompt for descriptions; instead clear the description of the first split.
       (description-editor
        (format
         "sh %s/rc/tools/jj-split-editor %s %s"
         my/--parent-directory
         is-description-empty
         state-file))
       )
    (and
     (my/patch
      (format
       "JJ_EDITOR=%s"
       (shell-quote-argument description-editor 'POSIX))
      "jj"
      "split"
      "-r"
      revision
      (format
       "--tool=%s/rc/tools/jj-split-tool"
       my/--parent-directory))
     ;; The first split will inherit the change ID from this diff, if
     ;; any. But typically -- when the diff is from "jj show --git" --
     ;; the remaining diff corresponds to the second split.  Update the
     ;; change ID accordingly. Among other things, this means that multiple
     ;; successive splits will create a simple, linear history.
     (when
         (and nil
              (not (string-equal revision "@")))
       (save-mark-and-excursion
         (progn
           (search-backward-regexp
            "^\\(?:commit\\|Change ID:\\) \\(\\w+\\)$")
           (end-of-line)
           (backward-word)
           (shell-command-on-region
            (point)
            (line-end-position)
            (format
             "jj log --no-graph --ignore-working-copy -r %s+ -T change_id"
             revision)
            nil
            'REPLACE)
           )
         )
       ))))

