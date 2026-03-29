source /usr/share/cachyos-fish-config/cachyos-config.fish

# overwrite greeting
# potentially disabling fastfetch
#function fish_greeting
#    # smth smth
#end

#alias godot='flatpak run org.godotengine.GodotSharp'
alias spotify='flatpak run com.spotify.Client'

if status is-interactive
    keychain --eval --quiet id_ed25519 | source
end
