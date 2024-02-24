declare-option -docstring "name of the client in which all source code jumps will be executed" \
    str jumpclient
declare-option -docstring "name of the client in which utilities display information" \
    str toolsclient

provide-module jump %{

declare-option -docstring %{
    pattern describing the default buffer used by jump-next and jump-previous
} regex jump_buffers

declare-option -hidden int jump_current_line 0

define-command -hidden jump %{
    evaluate-commands -save-regs a %{ # use evaluate-commands to ensure jumps are collapsed
        try %{
            evaluate-commands -draft %{
                execute-keys ',xs^([^:\n]+):(\d+):(\d+)?<ret>'
                set-register a %reg{1} %reg{2} %reg{3}
            }
            set-option buffer jump_current_line %val{cursor_line}
            evaluate-commands -try-client %opt{jumpclient} -verbatim -- edit -existing -- %reg{a}
            try %{ focus %opt{jumpclient} }
        }
    }
}

define-command jump-next -params 0..1 -docstring %{
    jump-next [<bufname>]: jump to next location listed in the given buffer

    <bufname> defaults to the last buffer whose name matches the 'jump_buffers' option
    See also ithe 'grep' command.
} %{
    evaluate-commands %sh{
        if [ $# -eq 0 ]; then
            echo require-module buffer
            echo buffer-with-latest %opt{jump_buffers} jump-next
            exit
        fi
        echo '
            evaluate-commands -try-client %opt{jumpclient} -save-regs / %{
                buffer %arg{1}
                jump-select-next
                jump
            }
            try %{
                evaluate-commands -client %opt{toolsclient} %{
                    buffer %arg{1}
                    execute-keys gg %opt{jump_current_line}g
                }
            }
        '
    }
}
complete-command jump-next buffer
define-command -hidden jump-select-next %{
    # First jump to end of buffer so that if jump_current_line == 0
    # 0g<a-l> will be a no-op and we'll jump to the first result.
    # Yeah, thats ugly...
    execute-keys ge %opt{jump_current_line}g<a-l> /^[^:\n]+:\d+:<ret>
}

define-command jump-previous -params 0..1 -docstring %{
    jump-previous [<bufname>]: jump to previous location listed in the given buffer

    <bufname> defaults to the last buffer whose name matches the 'jump_buffers' option
    See also ithe 'grep' command.
} %{
    evaluate-commands %sh{
        if [ $# -eq 0 ]; then
            echo require-module buffer
            echo buffer-with-latest %opt{jump_buffers} jump-previous
            exit
        fi
        echo '
            evaluate-commands -try-client %opt{jumpclient} -save-regs / %{
                buffer %arg{1}
                jump-select-previous
                jump
            }
            try %{
                evaluate-commands -client %opt{toolsclient} %{
                    buffer %arg{1}
                    execute-keys gg %opt{jump_current_line}g
                }
            }
        '
    }
}
complete-command jump-previous buffer
define-command -hidden jump-select-previous %{
    # See comment in jump-select-next
    execute-keys ge %opt{jump_current_line}g<a-h> <a-/>^[^:\n]+:\d+:<ret>
}

define-command jump-buffer-pop -docstring %{
    delete the last buffer whose name matches the 'jump_buffers' option.
    Activate the new last buffer in the client specified in the 'toolsclient'
    option. If the active client is different from 'toolsclient', jump to
    the current location.
} %{
    require-module buffer
    buffer-with-latest %opt{jump_buffers} delete-buffer
    try %{
        evaluate-commands -save-regs b %{
            buffer-with-latest %opt{jump_buffers} set-register b
            evaluate-commands -try-client %opt{toolsclient} -verbatim buffer %reg{b}
            evaluate-commands -try-client %opt{jumpclient} %{
                evaluate-commands %sh{
                    if [ -n "${kak_opt_toolsclient}" ] &&
                    [ "${kak_client}" != "${kak_opt_toolsclient}" ]; then
                        echo buffer %reg{b}
                        echo jump
                    fi
                }
            }
            echo -markup {Information}{\}returned to buffer %reg{b}
        }
    } catch %{
        echo -markup {Information}no jump buffer remaining
    }
}

}

hook -once global KakBegin .* %{ require-module jump }
