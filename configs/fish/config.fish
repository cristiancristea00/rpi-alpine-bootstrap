set -g fish_greeting

set -U fish_prompt_pwd_dir_length 0

# Common eza options
set -g COMMON_OPTIONS_EZA --absolute=off --classify=never --long --colour=always --icons=always --no-quotes --sort=name --group-directories-last --header --octal-permissions --no-filesize --no-time --no-git

# Common fd options
set -g COMMON_OPTIONS_FD --hidden --color always --follow --prune

# Colored man pages
set -x MANPAGER "sh -c 'col -bx | bat -l man -p'"
set -x MANROFFOPT "-c"

# Functions using eza
function ll
    eza $COMMON_OPTIONS_EZA $argv
end

function la
    eza $COMMON_OPTIONS_EZA --all $argv
end

function lt
    eza $COMMON_OPTIONS_EZA --tree --level=2 $argv
end

function lta
    eza $COMMON_OPTIONS_EZA --tree --level=2 --all $argv
end

# Functions using fd
function ff
    fd $COMMON_OPTIONS_FD --type file $argv
end

function fd
    command fd $COMMON_OPTIONS_FD $argv
end

function fx
    command fd $COMMON_OPTIONS_FD --type executable $argv
end