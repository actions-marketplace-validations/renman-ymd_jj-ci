# Makes lib/ a module, each file under its own name: `lib jj root`, `lib log
# warn`. Useful to poke at the internals from a shell —
#
#   use ~/Scripts/jj-ci/lib
#   lib jj revisions 'reachable(@, mutable())'
#
# The internals themselves do not go through this file. They import the exact
# module they need (`use jj.nu`, `use log.nu *`), which keeps call sites reading
# as `jj root` and `warn "…"` rather than `lib jj root`, and keeps generic names
# like `root` and `revisions` out of any namespace but their own.

export use log.nu
export use jj.nu
export use config.nu
export use render.nu
export use cache.nu
export use plan.nu
export use exec.nu
export use runner.nu
export use detect.nu
