function ls
    # Basic `ls` options for a detailed, usually-colored, human-readable list.
    # --icons: Display file type icons (requires a Nerd Font in your terminal).
    # --group-directories-first: Puts directories before files.
    # --header: Show the header (total number of files, etc.).
    # --git: Show git status for files/directories.
    # --time-format=long-iso: More detailed timestamp.
    # --classify: Append file type indicators (like / for directories, * for executables).
    # --long: Detailed list format (`ls -l`).
    # --all: Show hidden files (`ls -a`).
    # If the user provides a -h or --help argument, run eza with help.
    if contains -- -h $argv -or contains -- --help $argv
        eza $argv
    else
        eza --long --all --header --group-directories-first --time-style=relative --git --icons --classify $argv
    end
end
