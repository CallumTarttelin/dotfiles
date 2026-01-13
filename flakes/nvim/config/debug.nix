{pkgs, ...}: {
  # Core DAP plugin - lazy load on keymap or command
  plugins.dap = {
    enable = true;
    lazyLoad.settings = {
      cmd = ["DapContinue" "DapToggleBreakpoint"];
      keys = [
        "<leader>dc"
        "<leader>db"
        "<leader>dB"
        "<leader>do"
        "<leader>di"
        "<leader>dO"
        "<leader>dr"
        "<leader>dl"
        "<leader>dt"
        "<leader>du"
      ];
    };

    # Rust/C/C++ via lldb-dap
    adapters.executables.lldb = {
      command = "${pkgs.lldb}/bin/lldb-dap";
    };

    configurations = {
      rust = [
        {
          name = "Launch";
          type = "lldb";
          request = "launch";
          program.__raw = ''
            function()
              return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/target/debug/', 'file')
            end
          '';
          cwd = "\${workspaceFolder}";
          stopOnEntry = false;
        }
      ];
    };

    # Sign customization
    signs = {
      dapBreakpoint = {
        text = "●";
        texthl = "DapBreakpoint";
      };
      dapBreakpointCondition = {
        text = "◐";
        texthl = "DapBreakpointCondition";
      };
      dapLogPoint = {
        text = "◆";
        texthl = "DapLogPoint";
      };
      dapStopped = {
        text = "→";
        texthl = "DapStopped";
        linehl = "DapStoppedLine";
      };
      dapBreakpointRejected = {
        text = "○";
        texthl = "DapBreakpointRejected";
      };
    };
  };

  # DAP UI
  plugins.dap-ui.enable = true;

  # Virtual text showing variable values
  plugins.dap-virtual-text.enable = true;

  # Go debugger (delve)
  plugins.dap-go.enable = true;

  # Python debugger (debugpy)
  plugins.dap-python.enable = true;

  # Debug keymaps
  keymaps = [
    {
      mode = "n";
      key = "<leader>dc";
      action.__raw = "function() require('dap').continue() end";
      options.desc = "[D]ebug [C]ontinue";
    }
    {
      mode = "n";
      key = "<leader>db";
      action.__raw = "function() require('dap').toggle_breakpoint() end";
      options.desc = "[D]ebug toggle [B]reakpoint";
    }
    {
      mode = "n";
      key = "<leader>dB";
      action.__raw = ''
        function()
          require('dap').set_breakpoint(vim.fn.input('Breakpoint condition: '))
        end
      '';
      options.desc = "[D]ebug conditional [B]reakpoint";
    }
    {
      mode = "n";
      key = "<leader>do";
      action.__raw = "function() require('dap').step_over() end";
      options.desc = "[D]ebug step [O]ver";
    }
    {
      mode = "n";
      key = "<leader>di";
      action.__raw = "function() require('dap').step_into() end";
      options.desc = "[D]ebug step [I]nto";
    }
    {
      mode = "n";
      key = "<leader>dO";
      action.__raw = "function() require('dap').step_out() end";
      options.desc = "[D]ebug step [O]ut";
    }
    {
      mode = "n";
      key = "<leader>dr";
      action.__raw = "function() require('dap').repl.open() end";
      options.desc = "[D]ebug [R]EPL";
    }
    {
      mode = "n";
      key = "<leader>dl";
      action.__raw = "function() require('dap').run_last() end";
      options.desc = "[D]ebug run [L]ast";
    }
    {
      mode = "n";
      key = "<leader>dt";
      action.__raw = "function() require('dap').terminate() end";
      options.desc = "[D]ebug [T]erminate";
    }
    {
      mode = "n";
      key = "<leader>du";
      action.__raw = "function() require('dapui').toggle() end";
      options.desc = "[D]ebug [U]I toggle";
    }
    {
      mode = ["n" "v"];
      key = "<leader>de";
      action.__raw = "function() require('dapui').eval() end";
      options.desc = "[D]ebug [E]val";
    }
  ];

  # Add which-key group for debug
  plugins.which-key.settings.spec = [
    {
      __unkeyed-1 = "<leader>d";
      group = "[D]ebug";
    }
  ];

  # Debug adapters and tools
  extraPackages = with pkgs; [
    # Go
    delve
    # Python
    python3Packages.debugpy
    # Rust/C/C++
    lldb
  ];
}
