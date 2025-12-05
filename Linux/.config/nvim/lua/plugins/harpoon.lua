return {
  "ThePrimeagen/harpoon",
  branch = "harpoon2",
  keys = function()
    local keys = {
      {
        "<leader>a",
        function()
          require("harpoon"):list():add()
        end,
        desc = "Add to Harpoon",
      },
      {
        "<leader>A",
        function()
          require("harpoon"):list():prepend()
        end,
        desc = "Prepent to Harpoon",
      },
      {
        "<C-e>",
        function()
          local harpoon = require("harpoon")
          harpoon.ui:toggle_quick_menu(harpoon:list())
        end,
        desc = "Harpoon Quick Menu",
      },
      -- not working because my terminal does not process control + number properly
      -- {
      --   "<C-1>",
      --   function()
      --     require("harpoon"):list():select(1)
      --   end,
      --   desc = "Harpoon to File 1",
      -- },
    }
    for i = 1, 9 do
      table.insert(keys, {
        "<leader>" .. i,
        function()
          require("harpoon"):list():select(i)
        end,
        desc = "Harpoon to File " .. i,
      })
    end
    return keys
  end,
}
