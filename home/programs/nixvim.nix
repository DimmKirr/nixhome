{ pkgs, ... }:
{
  enable = true;
  colorschemes.dracula.enable = true;

  opts = {
    number = true;
    relativenumber = true;
    shiftwidth = 2;
    tabstop = 2;
    expandtab = true;
    signcolumn = "yes";
    termguicolors = true;
    cursorline = true;
    scrolloff = 8;
    updatetime = 250;
    timeoutlen = 500;
    undofile = true;
    ignorecase = true;
    smartcase = true;
    splitright = true;
    splitbelow = true;
    breakindent = true;
  };

  globals.mapleader = " ";

  keymaps = [
    { mode = "n"; key = "<leader>e"; action = "<cmd>Neotree toggle<cr>"; options.desc = "File tree"; }
    { mode = "n"; key = "<leader>ff"; action = "<cmd>Telescope find_files<cr>"; options.desc = "Find files"; }
    { mode = "n"; key = "<leader>fg"; action = "<cmd>Telescope live_grep<cr>"; options.desc = "Live grep"; }
    { mode = "n"; key = "<leader>fb"; action = "<cmd>Telescope buffers<cr>"; options.desc = "Buffers"; }
    { mode = "n"; key = "<leader>fh"; action = "<cmd>Telescope help_tags<cr>"; options.desc = "Help"; }
    { mode = "n"; key = "<leader>fd"; action = "<cmd>Telescope diagnostics<cr>"; options.desc = "Diagnostics"; }
    { mode = "n"; key = "<leader>xx"; action = "<cmd>Trouble diagnostics toggle<cr>"; options.desc = "Diagnostics (Trouble)"; }
    { mode = "n"; key = "<leader>xd"; action = "<cmd>Trouble diagnostics toggle filter.buf=0<cr>"; options.desc = "Buffer diagnostics"; }
    { mode = "n"; key = "<Esc>"; action = "<cmd>nohlsearch<cr>"; options.desc = "Clear search"; }
  ];

  plugins = {
    lualine.enable = true;
    web-devicons.enable = true;

    neo-tree = {
      enable = true;
      closeIfLastWindow = true;
      filesystem.followCurrentFile.enabled = true;
    };

    telescope = {
      enable = true;
      extensions.fzf-native.enable = true;
      extensions.ui-select.enable = true;
      settings.defaults.mappings = {
        i."<Esc>".__raw = "require('telescope.actions').close";
        i."<C-q>".__raw = "require('telescope.actions').close";
        n."<Esc>".__raw = "require('telescope.actions').close";
        n."q".__raw = "require('telescope.actions').close";
      };
    };

    treesitter = {
      enable = true;
      settings.highlight.enable = true;
      settings.indent.enable = true;
    };

    lsp = {
      enable = true;
      servers = {
        gopls.enable = true;
        nixd.enable = true;
        basedpyright.enable = true;
        ts_ls.enable = true;
        yamlls.enable = true;
      };
      keymaps = {
        silent = true;
        lspBuf = {
          "K" = { action = "hover"; desc = "Hover docs"; };
          "grn" = { action = "rename"; desc = "Rename"; };
          "gra" = { mode = [ "n" "x" ]; action = "code_action"; desc = "Code action"; };
          "grD" = { action = "declaration"; desc = "Go to declaration"; };
        };
        diagnostic = {
          "<leader>q" = { action = "setloclist"; desc = "Quickfix list"; };
        };
        extra = [
          { mode = "n"; key = "grd"; action.__raw = "require('telescope.builtin').lsp_definitions"; options.desc = "Go to definition"; }
          { mode = "n"; key = "grr"; action.__raw = "require('telescope.builtin').lsp_references"; options.desc = "References"; }
          { mode = "n"; key = "gri"; action.__raw = "require('telescope.builtin').lsp_implementations"; options.desc = "Implementations"; }
          { mode = "n"; key = "gO"; action.__raw = "require('telescope.builtin').lsp_document_symbols"; options.desc = "Document symbols"; }
        ];
      };
    };

    blink-cmp = {
      enable = true;
      settings = {
        keymap.preset = "default";
        appearance.nerd_font_variant = "mono";
        completion.documentation = {
          auto_show = true;
          auto_show_delay_ms = 250;
        };
        sources = {
          default = [ "lsp" "path" "snippets" "buffer" ];
        };
        signature.enabled = true;
      };
    };

    luasnip.enable = true;
    friendly-snippets.enable = true;

    conform-nvim = {
      enable = true;
      settings = {
        notify_on_error = false;
        format_on_save = {
          timeout_ms = 500;
          lsp_format = "fallback";
        };
        formatters_by_ft = {
          go = [ "gofmt" ];
          python = [ "black" ];
          nix = [ "nixfmt" ];
          javascript = [ "prettier" ];
          typescript = [ "prettier" ];
          yaml = [ "yamlfmt" ];
        };
      };
    };

    fidget.enable = true;
    trouble.enable = true;
    which-key.enable = true;
    todo-comments.enable = true;
    gitsigns.enable = true;
    indent-blankline.enable = true;
    schemastore.enable = true;

    mini = {
      enable = true;
      modules = {
        ai = { n_lines = 500; };
        surround = { };
      };
    };
  };
}
