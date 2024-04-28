provide-module menu %§§

declare-option -hidden completions menu_completions
declare-option -hidden str menu_parent_buffer
declare-option -hidden str menu_select_first <c-n>

define-command menu -params 1.. -docstring %{
    menu <name1> <commands1> <name2> <commands2>...: display a
    menu buffer to execute selected commands
} %{
    evaluate-commands -save-regs '"' %{
        # Store arguments in a register to avoid hitting ARG_MAX.
        set-register dquote %arg{@}
        menu-impl %val{bufname}
    }
}

define-command menu-auto-single -params 2.. -docstring %{
    Same as menu but instantly validate if only one item is available.
} %{
   menu %arg{@}
   try %{
       execute-keys -draft %{%s\A(?:[^\n]*\n){2}\z}
       execute-keys -with-hooks -with-maps <ret>
   }
}

define-command -hidden menu-impl -params 1 %{
    edit! -scratch *menu*
    set-option buffer filetype menu
    set-option buffer menu_parent_buffer %arg{1}
    evaluate-commands -draft -save-regs e %{
        execute-keys %{%<a-p>a<ret><esc>H}

        set-register e nop
        try %{
            execute-keys <a-k>\n<ret>
            set-register e fail menu: newline in argument is not supported
        }
        %reg{e}

        evaluate-commands %sh{
            count=$kak_selection_count
            if [ $(( $count % 2 )) -ne 0 ]; then
                echo fail menu: wrong number of arguments
                exit
            fi
            printf 'execute-keys )'
            while [ $count -ne 0 ]; do
                printf ')<a-,>'
                count=$(( $count - 2 ))
            done
        }

        try %{
            execute-keys <a-k>\t<ret>
            set-register e fail menu: tab in label is not supported
        }
        %reg{e}

        execute-keys <a-J>c<tab><esc>&gjdgk i<c-u><esc>
    }
    menu-complete
    execute-keys -with-hooks i
}

hook global WinSetOption filetype=menu %{
    map buffer insert <ret> %{<a-semicolon>:execute-keys %opt{menu_select_first}<ret><esc>:menu-execute<ret>:delete-buffer *menu*<ret>}
    map buffer normal <ret> %{:menu-execute<ret>}
    set-option buffer completers option=menu_completions
    hook window NormalIdle .* menu-complete

    hook buffer InsertCompletionHide .* %{
        unset-option window menu_select_first
    }
}

define-command -hidden menu-execute %{
    evaluate-commands -save-regs a %{
        execute-keys -draft %{,<semicolon>xs^[^\n]*?\t([^\n]*)<ret>:set-register a %reg{1}<ret>}
        buffer %opt{menu_parent_buffer}
        evaluate-commands -- %reg{a}
    }
}

define-command -hidden menu-complete %{
    evaluate-commands -save-regs | %{
        set-register | %{
            exec >${kak_command_fifo}
            printf %s 'set-option buffer menu_completions %exp{1.1@%val{timestamp}}'
            awk '/./ {
                gsub(/\\/, "\\\\"); gsub(/\|/, "\\|");
                gsub(/'\''/, "'\'\''");
                printf " '\''%s|set-option window menu_select_first %%{}|{\\}%s'\''", $0, $0;
            }'
        }
        execute-keys -draft %{%<a-|><ret>}
    }
}
