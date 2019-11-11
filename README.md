# vim-crates

When maintaining Rust projects, this plugin helps with updating the dependencies
in `Cargo.toml` files. It uses the [crates.io](https://crates.io) API to get all
available versions of a crate and caches them.

_[curl](https://curl.haxx.se) needs to be installed._

- **Insert completion**

  If the cursor is on a [version requirement](https://doc.rust-lang.org/cargo/reference/specifying-dependencies.html#specifying-dependencies)
  and in insert mode, use `<c-x><c-u>` (hold <kbd>Ctrl</kbd> and hit
  <kbd>x</kbd> then <kbd>u</kbd>) to open a completion menu with all available
  versions (see `:h i_CTRL-X_CTRL-U`).

- **:CratesUp**

  Update the current dependency to the latest non-prerelease version.

- **:CratesToggle**

  For each dependency that is out-of-date, indicate the latest version as virtual
  text after the end of the line. Use it again to remove all indicators. This is
  a [Nvim](https://github.com/neovim/neovim/)-only feature.

  Customize the colors of the indicators like this:

    ```vim
    highlight Crates ctermfg=green ctermbg=NONE cterm=NONE
    " or link it to another highlight group
    highlight link Crates WarningMsg
    ```
  Use `:verb CratesToggle` to see debug messages.

Inspired by [serayuzgur/crates](https://github.com/serayuzgur/crates).

Happy 🦀 everyone!

## Configuration

Automatically run `:CratesToggle` when opening a `Cargo.toml` file:

```vim
if has('nvim')
  autocmd BufRead Cargo.toml call crates#toggle()
endif
```

## Demo

![](https://raw.githubusercontent.com/mhinz/vim-crates/master/demo.gif)
