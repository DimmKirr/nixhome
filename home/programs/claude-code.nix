# Actual claude-code config is in ~/.claude/.claude.json
{pkgs, ...}:
let
  jsonFormat = pkgs.formats.json {};

  claudeConfig = {
    preferredNotifChannel = "terminal_bell";
    permissions = {
      allow = [
        "Read(~/.zshrc)"
        "Bash(find:*)"
        "Bash(rm:*)"
        "Bash(sed:*)"
        "Bash(ls:*)"
        "Bash(task:*)"
        "Bash(curl:*)"
        "Bash(grep:*)"
        "Bash(tree:*)"
      ];
    };


    mcpServers = {
      sequential-thinking = {
        command = "npx";
        args = [
          "-y"
          "@modelcontextprotocol/server-sequential-thinking"
        ];
      };
    };


#    env = {
#      CLAUDE_CODE_ENABLE_TELEMETRY = "1";
#      OTEL_METRICS_EXPORTER = "otlp";
#    };
  };

  generatedClaudeJSON = jsonFormat.generate "settings.local.json" claudeConfig;
in {
  home.file.".claude/settings.local.json".source = generatedClaudeJSON;
}
