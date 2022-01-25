# Colorscheme for light-theme terminal colors.
# This uses default background (expected to be white) so it has higher
# contrast than the "greyscale" theme.

# For Code
face global value default
face global type rgb:777777
face global variable rgb:777777
face global module rgb:777777
face global function rgb:777777
face global string rgb:888888
face global keyword rgb:666666
face global operator default
face global attribute rgb:777777
face global comment rgb:777777
face global documentation comment
face global meta rgb:888888
face global builtin default+b

# For markup
face global title rgb:666666
face global header rgb:777777
face global mono rgb:777777
face global block rgb:777777
face global link rgb:777777
face global bullet rgb:777777
face global list rgb:777777

# builtin faces
face global Default default,default
face global PrimarySelection black,rgb:cccccc+fg
face global SecondarySelection black,rgb:e0e0e0+fg
face global PrimaryCursor default,default+rfg
face global SecondaryCursor white,rgb:777777+fg
face global PrimaryCursorEol black,rgb:777777+fg
face global SecondaryCursorEol black,rgb:777777+fg
face global LineNumbers rgb:666666,default
face global LineNumberCursor default,default+r
face global MenuForeground white,black
face global MenuBackground black,rgb:dddddd
face global MenuInfo default
face global Information black,white
face global Error white,black
face global DiagnosticError default
face global DiagnosticWarning default
face global StatusLine rgb:666666,default
face global StatusLineMode rgb:666666,default
face global StatusLineInfo rgb:666666,default
face global StatusLineValue rgb:666666,default
face global StatusCursor black,rgb:666666
face global Prompt rgb:666666,default
face global MatchingChar default,default+b
face global Whitespace default,default+fd
face global BufferPadding rgb:666666,default
