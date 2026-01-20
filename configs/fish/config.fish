# Disable greeting message
set -g fish_greeting

# Show full path in prompt
set -U fish_prompt_pwd_dir_length 0

# Common eza options
set -g COMMON_OPTIONS_EZA --absolute=off --classify=never --long --colour=always --icons=always --no-quotes --sort=name --group-directories-last --header --octal-permissions --no-filesize --no-time --no-git

# Common fd options
set -g COMMON_OPTIONS_FD --hidden --color always --follow --prune

# Coloured man pages using bat
set -x MANPAGER "sh -c 'col -bx | bat -l man -p'"
set -x MANROFFOPT "-c"

# Functions using eza
function ll
    command eza $COMMON_OPTIONS_EZA $argv
end

function la
    command eza $COMMON_OPTIONS_EZA --all $argv
end

function lt
    command eza $COMMON_OPTIONS_EZA --tree --level=2 $argv
end

function lta
    command eza $COMMON_OPTIONS_EZA --tree --level=2 --all $argv
end

# Functions using fd
function ff
    command fd $COMMON_OPTIONS_FD --type file $argv
end

function fd
    command fd $COMMON_OPTIONS_FD $argv
end

function fx
    command fd $COMMON_OPTIONS_FD --type executable $argv
end

# Quick navigation aliases
function ..
    cd ..
end

function ...
    cd ../..
end

function ....
    cd ../../..
end