{
  perSystem = {pkgs, ...}: {
    packages.firefox-work = pkgs.writeShellScriptBin "firefox-work" ''
      set -eu

      profile_path="''${FIREFOX_WORK_PROFILE_PATH:-$HOME/.local/share/firefox-work-profile}"
      ${pkgs.coreutils}/bin/mkdir -p "$profile_path"

      firefox_args=(
        --name firefox-work
        --profile "$profile_path"
      )
      if [ ! -e "$profile_path/lock" ] && [ ! -L "$profile_path/lock" ]; then
        firefox_args+=(--new-instance)
      fi

      exec ${pkgs.coreutils}/bin/env \
        MOZ_DBUS_REMOTE=1 \
        MOZ_DBUS_APP_NAME=firefox_work \
        ${pkgs.firefox}/bin/firefox \
        "''${firefox_args[@]}" \
        "$@"
    '';
  };

  flake.nixosModules.firefox-work-profile = {
    config,
    lib,
    pkgs,
    self,
    ...
  }: let
    cfg = config.features.firefox-work-profile;
    routesSecret = config.age.secrets.work-url-routes.path;

    configuredFirefoxWork = pkgs.writeShellScriptBin "firefox-work" ''
      set -eu

      profile_path=${lib.escapeShellArg cfg.profilePath}
      ${pkgs.coreutils}/bin/mkdir -p "$profile_path"

      firefox_args=(
        --name firefox-work
        --profile "$profile_path"
      )
      if [ ! -e "$profile_path/lock" ] && [ ! -L "$profile_path/lock" ]; then
        firefox_args+=(--new-instance)
      fi

      exec ${pkgs.coreutils}/bin/env \
        MOZ_DBUS_REMOTE=1 \
        MOZ_DBUS_APP_NAME=firefox_work \
        ${pkgs.firefox}/bin/firefox \
        "''${firefox_args[@]}" \
        "$@"
    '';

    workUrlRouter = pkgs.writeShellScriptBin "work-url-router" ''
      set -eu

      exec ${pkgs.python3}/bin/python3 - ${lib.escapeShellArg routesSecret} ${lib.escapeShellArg "${configuredFirefoxWork}/bin/firefox-work"} ${lib.escapeShellArg "${pkgs.firefox}/bin/firefox"} ${lib.escapeShellArg "${pkgs.libnotify}/bin/notify-send"} "$@" <<'PY'
      import fnmatch
      import json
      import subprocess
      import sys
      from urllib.parse import urlparse


      def notify(notify_send, message):
          try:
              subprocess.run(
                  [notify_send, "Work URL Router", message],
                  check=False,
                  stdout=subprocess.DEVNULL,
                  stderr=subprocess.DEVNULL,
              )
          except Exception:
              pass


      def load_rules(path):
          with open(path, "r", encoding="utf-8") as route_file:
              config = json.load(route_file)

          rules = config.get("rules")
          if not isinstance(rules, list):
              raise ValueError("missing rules list")

          normalized = []
          for rule in rules:
              if not isinstance(rule, dict):
                  raise ValueError("rule must be an object")

              rule_type = rule.get("type")
              value = rule.get("value")
              if rule_type not in ("prefix", "glob"):
                  raise ValueError("unsupported rule type")
              if not isinstance(value, str) or not value:
                  raise ValueError("rule value must be a non-empty string")

              normalized.append((rule_type, value))

          return normalized


      def is_http_url(url):
          parsed = urlparse(url)
          return parsed.scheme in ("http", "https") and bool(parsed.netloc)


      def matches(url, rules):
          if not is_http_url(url):
              return False

          for rule_type, value in rules:
              if rule_type == "prefix" and url.startswith(value):
                  return True
              if rule_type == "glob" and fnmatch.fnmatchcase(url, value):
                  return True

          return False


      def open_url(browser, url):
          subprocess.Popen(
              [browser, "--new-tab", url],
              stdout=subprocess.DEVNULL,
              stderr=subprocess.DEVNULL,
          )


      def main():
          if len(sys.argv) < 5:
              return 64

          routes_path = sys.argv[1]
          work_browser = sys.argv[2]
          normal_browser = sys.argv[3]
          notify_send = sys.argv[4]
          urls = sys.argv[5:]

          try:
              rules = load_rules(routes_path)
              routes_available = True
          except Exception:
              rules = []
              routes_available = False
              notify(notify_send, "Route secret is missing or malformed; opening links in normal Firefox.")

          for url in urls:
              browser = work_browser if routes_available and matches(url, rules) else normal_browser
              open_url(browser, url)

          return 0


      if __name__ == "__main__":
          raise SystemExit(main())
      PY
    '';
  in {
    options.features.firefox-work-profile = {
      enable = lib.mkEnableOption "Firefox work profile and URL routing";

      profilePath = lib.mkOption {
        type = lib.types.str;
        default = "${config.home-manager.users.tarttelin.xdg.dataHome}/firefox-work-profile";
        description = "Firefox profile directory used by the work launcher.";
      };

      routesSecretFile = lib.mkOption {
        type = lib.types.path;
        default = ../../secrets/work-url-routes.age;
        description = "Age-encrypted JSON route list for work URL routing.";
      };
    };

    config = lib.mkIf cfg.enable {
      age.secrets.work-url-routes = {
        file = cfg.routesSecretFile;
        owner = "tarttelin";
        group = "users";
        mode = "0400";
      };

      home-manager.users.tarttelin = {
        home.packages = [
          configuredFirefoxWork
          workUrlRouter
        ];

        xdg.desktopEntries = {
          firefox-work = {
            name = "Firefox Work";
            genericName = "Web Browser";
            exec = "${configuredFirefoxWork}/bin/firefox-work %U";
            icon = "firefox";
            terminal = false;
            categories = [
              "Network"
              "WebBrowser"
            ];
            startupNotify = true;
            settings.StartupWMClass = "firefox-work";
          };

          work-url-router = {
            name = "Work URL Router";
            exec = "${workUrlRouter}/bin/work-url-router %U";
            terminal = false;
            noDisplay = true;
            mimeType = [
              "x-scheme-handler/http"
              "x-scheme-handler/https"
            ];
          };
        };

        xdg.mimeApps.defaultApplications = {
          "x-scheme-handler/http" = lib.mkForce ["work-url-router.desktop"];
          "x-scheme-handler/https" = lib.mkForce ["work-url-router.desktop"];
        };
      };
    };
  };
}
