mod cmd "cmd/justfile"
mod macosapp "macosapp/justfile"
mod swift "tool/swift/justfile"

# List root recipes and registered submodules.
default:
    @just --list --list-submodules
