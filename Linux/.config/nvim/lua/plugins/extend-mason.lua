return {
  "mason-org/mason.nvim",
  opts = {
    registries = {
      "github:mason-org/mason-registry",
    },
    ensure_installed = {
      "html-lsp",
      "css-lsp",
      "json-lsp",
    },
  },
}
