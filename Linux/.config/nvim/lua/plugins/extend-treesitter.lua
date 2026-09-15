return {
  "nvim-treesitter/nvim-treesitter",
  opts = {
    ensure_installed = {
      "html",
      "css",
      "c_sharp",
      "razor",
    },
    sync_install = false,
    auto_install = false,
    highlight = {
      enable = true,
    },
  },
}
