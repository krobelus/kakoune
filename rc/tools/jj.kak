# Jujutsu - https://jj-vcs.github.io/jj/latest/

hook -group jj-diff-highlight global WinSetOption filetype=jj-diff %{
    require-module diff
    add-highlighter window/jj-diff-ref-diff ref diff
    hook -once -always window WinSetOption filetype=.* %{
        remove-highlighter window/jj-diff-ref-diff
    }
}

hook global WinSetOption filetype=jj-diff %{
    map buffer normal <ret> %{:jj-diff-goto-source<ret>} -docstring 'Jump to source from jj diff'
    hook -once -always window WinSetOption filetype=.* %{
        unmap buffer normal <ret> %{:jj-diff-goto-source<ret>}
    }
}

define-command -hidden -docstring %{
    call diff-jump with the jj workspace root
} jj-diff-goto-source %{
    require-module diff
    diff-jump %sh{ jj --ignore-working-copy workspace root }
}

declare-option -hidden -docstring %{
    whether to suppress output of successful jj commands
} bool jj_silent false

define-command jj -params 1.. -docstring %{
    jj [<arguments>]: Jujutsu wrapper
    All optional arguments are forwarded to the jj utility.

    See ':doc jj' for help.

    Available commands:
        abandon        - abandon a revision
        absorb         - move changes from a revision into the stack of mutable revisions
        backout        - apply the reverse of a revision on top of another revision
        b, bookmark    - manage bookmarks
        desc, describe - update the change description or other metadata
        diff           - compare file contents between two revisions
        edit           - sets the specified revision as the working-copy revision
        evolog         - show how a change has evolved over time
        log            - show revision history
        new            - create an empty change and (by default) edit it in the working copy
        next           - move the working copy commit to the child revision
        op, operation  - commands for working with the operation log
        parallelize    - parallelize revisions by making them siblings
        prev           - move the working copy commit to the parent revision
        rebase         - move revisions to different parent(s)
        show           - show commit description and changes in a revision
        split          - split selected lines into a separate revision
        squash         - move changes from a revision into another revision
        st, status     - show high-level repo status
        undo           - undo an operation (shortcut for 'jj op undo')
        -h, --help     - print help (see more with '--help')
} %{ evaluate-commands %sh{
    kakquote() {
        printf "%s" "$1" | sed "s/'/''/g; 1s/^/'/; \$s/\$/'/"
    }

    check_output() {
        local buffered_error=/dev/null
        if ! $INPARAM_combine_output; then
            buffered_error=$(mktemp "${TMPDIR:-/tmp}"/kak-jj-error.XXXXXXXX)
        fi
        OUTPARAM_jj_output=$(
            if $INPARAM_combine_output; then
                "$@" 2>&1
            else
                "$@" 2>"$buffered_error"
            fi
            local status=$?
            printf .
            exit $status
        )
        local status=$?
        OUTPARAM_jj_output=${OUTPARAM_jj_output%.}

        if [ $status -ne 0 ] || ! $INPARAM_silent; then
            echo 'echo -debug <<<'
            printf 'echo -debug $'
            for arg; do
                printf ' %s' "$(kakquote "$arg")"
            done
            printf '\n'
            echo "echo -debug -- $(kakquote "$OUTPARAM_jj_output$(cat "$buffered_error")")"
            echo 'echo -debug >>>'
        fi

        if [ $status -ne 0 ]; then
            echo "fail $(kakquote "failed to run $*, see the *debug* buffer")"
            return 1
        fi
    }

    jj_with_transient_output() {
        local silent=${kak_opt_jj_silent}
        if INPARAM_combine_output=true INPARAM_silent=$silent check_output jj "$@" && ! $silent; then
            echo info -title "$(kakquote "\$ jj $*")" -- "$(kakquote "$OUTPARAM_jj_output")"
        fi
    }

    jj_with_buffer_output() {
        local output=$(mktemp -d "${TMPDIR:-/tmp}"/kak-jj.XXXXXXXX)/fifo
        mkfifo ${output}
        # Hack-ish: if the kak-ansi plugin is installed, turn on colors by default.
        # If jj prints invalid UTF-8, this might truncate the output.
        # NOTE: going forward, we should probably require an 'ansi' module.
        local color=
        local render_colors=
        if [ -n "${kak_opt_ansi_filter}" ]; then
            color=--color=always
            render_colors='
                ansi-enable
                # Undo the cursor-movement after the initial ansi-render.
                hook -once buffer BufReadFifo .* %exp{
                    execute-keys -client %val{client} gk
                }
            '
        fi
        (
            trap - INT QUIT
            jj $color "$@" >${output} 2>&1 &
        ) >/dev/null 2>&1 </dev/null
        printf %s "
            evaluate-commands -try-client '${kak_opt_docsclient}' '
                edit! -fifo ${output} *jj*
                $render_colors
                set-option buffer filetype %{${INPARAM_filetype}}
                hook -always -once buffer BufCloseFifo .* ''
                    nop %sh{ rm -r $(dirname ${output}) }
                ''
            '
        "
    }

    jj_bookmark() {
        case "$2" in
            (list | l) jj_with_buffer_output "$@" ;;
            (*) jj_with_transient_output "$@" ;;
        esac
    }

    shell() {
        echo ${KAKOUNE_POSIX_SHELL:-/bin/sh}
    }

    jj_describe() {
        if printf %s\\n "$@" | grep -qE '^(--message(=|$)|-m)'; then
            jj_with_transient_output "$@"
            return
        fi
        local msgfile=$(mktemp "${TMPDIR:-/tmp}"/kak-jj-describe.XXXXXXXX)
        if ! JJ_EDITOR=cat INPARAM_combine_output=false INPARAM_silent=true check_output jj --ignore-working-copy "$@"; then
            return
        fi
        printf %s "$OUTPARAM_jj_output" >$msgfile
        printf %s "
            edit $msgfile
            declare-option str-list jj_describe_args %arg{@}
            set-option buffer filetype jj-describe
            hook buffer BufWritePost .* %{
                evaluate-commands %{
                    set-option local jj_silent true
                    jj __kakoune_finish_describe $msgfile %opt{jj_describe_args}
                }
            }
            hook buffer BufClose .* %{ nop %sh{ rm -f $msgfile } }
        "
    }

    jj_finish_describe() {
        local msgfile=$2
        shift 2
        JJ_EDITOR="cp $msgfile" jj_with_transient_output "$@"
    }

    jj_operation() {
        case "$2" in
            (diff | log | show) jj_with_buffer_output "$@" ;;
            (*) jj_with_transient_output "$@" ;;
        esac
    }

    jj_show() {
        INPARAM_filetype=jj-diff
        jj_with_buffer_output "$@"
    }

    jj_squash() {
        (
            escape2() { printf %s "$*" | sed "s/'/''''/g"; }
            escape3() { printf %s "$*" | sed "s/'/''''''''/g"; }
            output=$(
                JJ_EDITOR="$(shell) ${kak_runtime}/rc/tools/blocking-editor-in-client ${kak_session} ${kak_client}" \
                    jj "$@" 2>&1
            )
            status=$?
            response="
                echo -debug ''<<<''
                echo -debug ''\$ $(escape2 jj "$@")''
                echo -debug -- ''$(escape2 "$output")''
                echo -debug ''>>>''
            "
            if [ $status -ne 0 ]; then
                response="$response
                    hook -once buffer NormalIdle .* ''
                        echo -markup ''''{Error}{\\}failed to run $(escape3 jj "$@"), see *debug* buffer''''
                    ''
                "
            fi
            echo "evaluate-commands -client ${kak_client} '$response'" | kak -p ${kak_session}
        ) >/dev/null 2>&1 </dev/null &
    }

    jj_split() {
        local parallel=false
        local has_fileset_argument=false
        local seen_ddash=false
        shift
        for arg; do
            if $seen_ddash; then
                has_fileset_argument=true
                break
            fi
            case "$arg" in
                (--)
                    seen_ddash=true
                    ;;
                (-p | --parallel)
                    parallel=true
                    ;;
                (-*)
                    echo "fail jj split: unsupported argument $(kakquote "$arg")"
                    ;;
                (*)
                    has_fileset_argument=true
                    break
                    ;;
            esac
        done
        # undo shift
        set -- split "$@"
        if $has_fileset_argument; then
            jj_with_transient_output jj "$@"
            return
        fi
        echo >${kak_command_fifo} "
            evaluate-commands -draft %{
                try %{
                    execute-keys %{<a-/>^(?:commit|Change ID:) \S+<ret>}
                    execute-keys %{1s^(?:commit|Change ID:) (\S+)<ret>}
                    echo -to-file ${kak_response_fifo} -- %val{selection}
                } catch %{
                    # assume we're splitting the working copy commit
                    echo -to-file ${kak_response_fifo} @
                }
            }
        "
        local revision=$(cat ${kak_response_fifo})
        local statefile=$(mktemp "${TMPDIR:-/tmp}"/kak-jj-split.XXXXXXXX)
        echo "require-module patch"
        empty_description=false
        if [ -z "$(jj log --no-graph --ignore-working-copy -r ${revision} -T description)" ]; then
            empty_description=true
        fi
        echo "patch %exp{JJ_EDITOR='$(shell) %val{runtime}/rc/tools/jj-split-editor $empty_description ${statefile}'} \
                jj %arg{@} -r $revision %exp{--tool=%val{runtime}/rc/tools/jj-split-tool}"
        # The first split will inherit the change ID from this diff, if
        # any. But typically -- when the diff is from "jj show --git" --
        # the remaining diff corresponds to the second split.  Update the
        # change ID accordingly. Among other things, this means that multiple
        # successive splits will create a simple, linear history.
        if [ "$revision" != @ ] && ! $parallel; then {
            echo "evaluate-commands -draft -save-regs | %{
                try %{
                    execute-keys %{<a-/>^Change ID: \S+<ret>}
                    execute-keys %{1s^Change ID: (\S+)<ret>}
                    set-register | %{
                        jj log --no-graph --ignore-working-copy -r ${revision}+ -T change_id
                    }
                    execute-keys |<ret>
                }
            }"
        } fi
    }

    INPARAM_filetype=

    case "$2" in
        (-h | --help)
            jj_with_buffer_output "$@"
            exit
            ;;
    esac
    case "$1" in
        (abandon) jj_with_transient_output "$@" ;;
        (absorb) jj_with_transient_output "$@" ;;
        (backout) jj_with_transient_output "$@" ;;
        (b | bookmark) jj_bookmark "$@" ;;
        (describe) jj_describe "$@" ;;
        (__kakoune_finish_describe) jj_finish_describe "$@" ;;
        (diff) jj_show "$@" ;;
        (edit) jj_with_transient_output "$@" ;;
        (evolog) jj_with_buffer_output "$@" ;;
        (log) jj_with_buffer_output "$@" ;;
        (new) jj_with_transient_output "$@" ;;
        (next) jj_with_transient_output "$@" ;;
        (op | operation) jj_operation "$@" ;;
        (parallelize) jj_with_transient_output "$@" ;;
        (prev) jj_with_transient_output "$@" ;;
        (rebase) jj_with_transient_output "$@" ;;
        (show) jj_show "$@" ;;
        (squash) jj_squash "$@" ;;
        (split) jj_split "$@" ;;
        (st | status) jj_with_buffer_output "$@" ;;
        (undo) jj_with_transient_output "$@" ;;
        (-h | --help) jj_with_buffer_output "$@" ;;
        (*) printf "fail unknown jj command '%s'\n" "$cmd"
    esac
} }

complete-command jj shell-script-candidates %{
    if [ ${kak_token_to_complete} -eq 0 ]; then {
        printf %s\\n \
            abandon \
            absorb \
            backout \
            b bookmark \
            describe \
            diff \
            edit \
            evolog \
            log \
            new \
            next \
            op operation \
            parallelize \
            prev \
            rebase \
            show \
            squash \
            split \
            st status \
            undo \
            -h --help \
        ; return
    } fi
    COMPLETE=fish jj --ignore-working-copy -- jj "$@" | sed 's,\t.*,,g' # Remove descriptions.
}
