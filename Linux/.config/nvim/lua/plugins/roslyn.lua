-- Official Roslyn C# LSP (with Razor/Blazor support via co-hosting)
-- https://github.com/seblyng/roslyn.nvim
--
-- Razor/CSHTML support is built into roslyn.nvim (co-hosting), superseding
-- the now-deprecated tris203/rzls.nvim.
--
-- Language server install (manual dotnet tool, Azure DevOps feed, required
-- for current Razor support and requires the .NET 10 SDK):
--   dotnet tool install -g roslyn-language-server --prerelease \
--     --source https://pkgs.dev.azure.com/azure-public/vside/_packaging/vs-impl/nuget/v3/index.json

return {
  "seblyng/roslyn.nvim",
  ft = { "cs", "razor" },
  init = function()
    -- Register Razor file types before the plugin loads.
    vim.filetype.add({
      extension = {
        razor = "razor",
        cshtml = "razor",
      },
    })
  end,
  ---@module 'roslyn.config'
  ---@type RoslynNvimConfig
  opts = {},
  config = function(_, opts)
    require("roslyn").setup(opts)

    vim.lsp.config("roslyn", {
      settings = {
        ["csharp|background_analysis"] = {
          dotnet_analyzer_diagnostics_scope = "fullSolution",
          dotnet_compiler_diagnostics_scope = "fullSolution",
        },
        ["csharp|inlay_hints"] = {
          csharp_enable_inlay_hints_for_implicit_object_creation = true,
          csharp_enable_inlay_hints_for_implicit_variable_types = true,
          csharp_enable_inlay_hints_for_lambda_parameter_types = true,
          csharp_enable_inlay_hints_for_types = true,
          dotnet_enable_inlay_hints_for_indexer_parameters = true,
          dotnet_enable_inlay_hints_for_literal_parameters = true,
          dotnet_enable_inlay_hints_for_object_creation_parameters = true,
          dotnet_enable_inlay_hints_for_other_parameters = true,
          dotnet_enable_inlay_hints_for_parameters = true,
          dotnet_suppress_inlay_hints_for_parameters_that_differ_only_by_suffix = true,
          dotnet_suppress_inlay_hints_for_parameters_that_match_argument_name = true,
          dotnet_suppress_inlay_hints_for_parameters_that_match_method_intent = true,
        },
        ["csharp|code_lens"] = {
          dotnet_enable_references_code_lens = true,
        },
      },
    })
  end,
}
