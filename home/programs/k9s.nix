{pkgsUnstable, ...}: {
  enable = true;
  package = pkgsUnstable.k9s;

  # Renamed from hotkey.hotKeys to hotKeys in home-manager 25.11+
  hotKeys = {
    f1 = {
      shortCut = "F1";
      description = "Viewing pods";
      command = "pods";
    };

    f2 = {
      shortCut = "F2";
      description = "View Deployments";
      command = "dp";
    };

    f3 = {
      shortCut = "F3";
      description = "View CronJobs";
      command = "cronjob";
    };

    f4 = {
      shortCut = "F4";
      description = "View Jobs";
      command = "job";
    };

    f5 = {
      shortCut = "F5";
      description = "View Nodes";
      command = "node";
    };

    f6 = {
      shortCut = "F6";
      description = "View ConfigMaps";
      command = "cm";
    };

    f7 = {
      shortCut = "F7";
      description = "View Secrets";
      command = "secret";
    };

    f8 = {
      shortCut = "F8";
      description = "HPA";
      command = "hpa";
    };

    f9 = {
      shortCut = "F9";
      description = "Node";
      command = "node";
    };
  };

  # Renamed from plugin to plugins in home-manager 25.11+
  plugins = {
    fred = {
      shortCut = "Ctrl-L";
      description = "Pod logs";
      scopes = ["po"];
      command = "kubectl";
      background = false;
      args = [
        "logs"
        "-f"
        "$NAME"
        "-n"
        "$NAMESPACE"
        "--context"
        "$CLUSTER"
      ];
    };
  };
}
