# Makes commands/ a module: each file is re-exported under its own name, so the
# root module calls `commands ci invoke`, `commands push invoke`, and so on.
#
# `export use` rather than `use`: a plain `use` would import them for this file
# only, and the root would see nothing.

export use ci.nu
export use push.nu
export use init.nu
export use install.nu
export use completions.nu
export use doctor.nu
