hook global BufCreate .*\.(diff|patch) %{
    set-option buffer filetype diff
}

hook global WinSetOption filetype=diff %{
    require-module diff
    map buffer normal <ret> :diff-jump<ret>
}

hook -group diff-highlight global WinSetOption filetype=diff %{
    add-highlighter window/diff ref diff
    hook -once -always window WinSetOption filetype=.* %{ remove-highlighter window/diff }
}

provide-module diff %§

add-highlighter shared/diff group
add-highlighter shared/diff/ regex "^\+[^\n]*\n" 0:green,default
add-highlighter shared/diff/ regex "^-[^\n]*\n" 0:red,default
add-highlighter shared/diff/ regex "^@@[^\n]*@@" 0:cyan,default
# If any trailing whitespace was introduced in diff, show it with red background
add-highlighter shared/diff/ regex "^\+[^\n]*?(\h+)\n" 1:default,red

define-command diff-jump -params .. -docstring %{
        diff-jump [<switches>] [<directory>]: edit the diff's source file at the cursor position.
        Paths are resolved relative to <directory>, or the current working directory if unspecified.

        Switches:
            -       jump to the old file instead of the new file
            -<num> strip <num> leading directory components, like -p<num> in patch(1). Defaults to 1 if there is a 'diff' line (as printed by 'diff -r'), or 0 otherwise.
    } %{
    evaluate-commands -draft -save-regs c %{
        # Save the column because we will move the cursor.
        set-register c %val{cursor_column}
        # If there is a "diff" line, we don't need to look further back.
        try %{
            execute-keys %{<a-l><semicolon><a-?>^(?:> )*diff\b<ret>x}
        } catch %{
            # A single file diff won't have a diff line. Start parsing from
            # the buffer start, so we can tell if +++/--- lines are headers
            # or content.
            execute-keys Gk
        }
        diff-parse BEGIN %{
            my $seen_ddash = 0;
            foreach (@ARGV) {
                if ($seen_ddash or !m{^-}) {
                    $directory = $_;
                } elsif ($_ eq "-") {
                    $version = "-", $other_version = "+";
                } elsif (m{^-(\d+)$}) {
                    $strip = $1;
                } elsif ($_ eq "--") {
                    $seen_ddash = 1;
                } else {
                    fail "unknown option: $_";
                }
            }
        } END %exp{
            my $file_column;
            if (not defined $file_line) {
                $file_line = "";
                $file_column = "";
            } else {
                my $diff_column = %reg{c};
                $file_column = $diff_column - 1; # Account for [ +-] diff prefix.
                # If the cursor was on a hunk header, go to the section header if possible.
                if ($diff_line_text =~ m{^(@@ -\d+(?:,\d+)? \+\d+(?:,\d+) @@ )([^\n]*)}) {
                    my $hunk_header_prefix = $1;
                    my $hunk_header_from_userdiff = $2;
                    open FILE, "<", $file or fail "failed to open file: $!: $file";
                    my @lines = <FILE>;
                    for (my $i = $file_line - 1; $i >= 0 and $i < scalar @lines; $i--) {
                        if ($lines[$i] !~ m{\Q$hunk_header_from_userdiff}) {
                            next;
                        }
                        $file_line = $i + 1;
                        # Re-add 1 because the @@ line does not have a [ +-] diff prefix.
                        $file_column = $diff_column + 1 - length $hunk_header_prefix;
                        last;
                    }
                }
            }
            printf "set-register c %%s $file_line $file_column\n", quote($file);
        } -- %arg{@}
        evaluate-commands -client %val{client} %{
            evaluate-commands -try-client %opt{jumpclient} %{
                edit -existing -- %reg{c}
            }
        }
    }
}
complete-command diff-jump file

define-command diff -docstring %{
    diff <old-file> [<new-file> [<bufname>]]: compare two files in a scratch buffer

    The current buffer's file be used if no new file is given.
    The scratch buffer will be called '*diff*' if not specified.
} -params 1.. %{
    evaluate-commands %sh{
        printf %s\\n "edit -scratch ${3:-'*diff*'}"
        printf %s\\n "set-option buffer filetype diff"
        shellquote() {
            printf "'%s'" "$(printf %s "$1" | sed "s/'/'\\''/g")"
        }
        printf "execute-keys %%{%%d!diff -u %s %s<ret>gk}\\n" \
                "$(shellquote "$1")" "$(shellquote "${2:-"${kak_buffile}"}")"
    }
}
complete-command diff file

define-command diff-jump-reverse -params 2 %{
    evaluate-commands -save-regs lc %{
        evaluate-commands -draft %{
            set-register l %val{cursor_line}
            set-register c %val{cursor_column}
            buffer %arg{1}
            execute-keys <percent>
            diff-parse BEGIN %exp{
                $in_reverse_version = "%arg{2}";
                if ($in_reverse_version eq "+") {
                    $version = "-";
                } else {
                    $version = "+";
                }
                $in_reverse_line = %reg{l};
                $in_reverse_column = %reg{c};
            } END %exp{
                print "set-register l $diff_line\n";
            }
        }
        evaluate-commands -try-client %opt{jumpclient} %{
            buffer %arg{1}
            execute-keys %exp{%reg{l}g}
        }
    }
}

define-command -hidden diff-jump-both -params 2 %{
    evaluate-commands -draft -save-regs con %{
        # Save the column because we will move the cursor.
        set-register c %val{cursor_column} # TODO
        # If there is a "diff" line, we don't need to look back any further.
        try %{
            execute-keys %{<a-l><semicolon><a-?>^(?:> )*diff\b<ret><a-x>}
        } catch %{
            # A single file diff won't have a diff line. Start parsing from
            # the buffer start, so we can tell if +++/--- lines are headers
            # or content.
            execute-keys Gk
        }
        diff-parse END %{
            printf "set-register o %s %d\n", quote($other_file), $other_file_line;
            printf "set-register n %s %d\n", quote($file), $file_line;
        }
        evaluate-commands -client %arg{1} %{ edit -existing -- %reg{o} }
        evaluate-commands -client %arg{2} %{ edit -existing -- %reg{n} }
    }
}

define-command -hidden diff-jump-other-version -params 2 %{
    evaluate-commands -save-regs lc %{
        evaluate-commands -draft %{
            set-register l %val{cursor_line}
            set-register c %val{cursor_column}
            buffer %arg{1}
            execute-keys <percent>
            diff-parse BEGIN %exp{
                $in_reverse_version = "%arg{2}";
                if ($in_reverse_version eq "+") {
                    $version = "-";
                } else {
                    $version = "+";
                }
                $in_reverse_line = %reg{l};
                $in_reverse_column = %reg{c};
            } END %exp{
                my $column = %reg{c} - 1; # Account for [ +-] diff prefix.
                print "set-register l $diff_line\n";
                printf "set-register c %%s %%d %%d\n", quote($file), $file_line, $column;
            }
        }
        evaluate-commands -client %opt{jumpclient} %{
            buffer %arg{1}
            execute-keys "%reg{l}g"
            edit -existing -- %reg{c}
        }
    }
}

declare-option -hidden line-specs diff_flags
define-command -hidden diff-show -params 3 %{
    evaluate-commands -save-regs on %{
        evaluate-commands -draft %{
            buffer %arg{1}
            execute-keys <percent>
            diff-parse BEGIN %{
                $flags = "";
                $other_flags = "";
            } END %{
                if ($version eq "-") {
                    ($flags, $other_flags) = ($other_flags, $flags);
                }
                printf "set-register o %s\n", $other_flags;
                printf "set-register n %s\n", $flags;
                exit;
            }
        }
        set-option "buffer=%arg{2}" diff_flags %val{timestamp} %reg{o}
        set-option "buffer=%arg{3}" diff_flags %val{timestamp} %reg{n}
    }
}

define-command -hidden diff-parse -params 2.. %{
    evaluate-commands -save-regs ae| %{
        set-register a %arg{@}
        set-register e nop
        set-register | %{
            eval set -- "$kak_quoted_reg_a"
            perl "${kak_runtime}/rc/filetype/diff-parse.pl" "$@" >"$kak_command_fifo"
        }
        execute-keys <a-|><ret>
        %reg{e}
    }
}

§

define-command \
    -docstring %{diff-select-file: Select surrounding patch file} \
    -params 0 \
    diff-select-file %{
                evaluate-commands -itersel -save-regs 'ose/' %{
        try %{
            execute-keys '"oZgl<a-?>^diff <ret>;"sZ' 'Ge"eZ'
            try %{ execute-keys '"sz?\n(?=diff )<ret>"e<a-Z><lt>' }
            execute-keys '"ez'
        } catch %{
            execute-keys '"oz'
            fail 'Not in a diff file'
        }
    }
}

define-command \
    -docstring %{diff-select-hunk: Select surrounding patch hunk} \
    -params 0 \
    diff-select-hunk %{
    evaluate-commands -itersel -save-regs 'ose/' %{
        try %{
            execute-keys '"oZgl<a-?>^@@ <ret>;"sZ' 'Ge"eZ'
            try %{ execute-keys '"sz?\n(?=diff )<ret>"e<a-Z><lt>' }
            try %{ execute-keys '"sz?\n(?=@@ )<ret>"e<a-Z><lt>' }
            execute-keys '"ez'
        } catch %{
            execute-keys '"oz'
            fail 'Not in a diff hunk'
        }
    }
}
