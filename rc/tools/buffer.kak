provide-module buffer %{

    define-command -hidden buffer-with-latest -params 2.. -docstring %{
        buffer-with-latest <bufname_regex> <cmd> [<arguments>]: run the given command,
        passing as final argument the last buffer that matches <bufname_regex>
    } %{
        evaluate-commands %sh{
            bufname_regex=$1
            shift
            cmd=$*
            eval set -- "${kak_quoted_buflist}"
            bufname=$(printf %s\\n "$@" | grep -Ex -- "${bufname_regex}" | tail -n 1)
            if [ -n "${bufname}" ]; then
                echo "$cmd '$(printf %s "$bufname" | sed "s/'/''/g")'"
            else
                echo "fail no buffer matching %arg{1}"
            fi
        }
    }

}
