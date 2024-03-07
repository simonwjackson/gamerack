inputs: {
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (pkgs.stdenv.hostPlatform) system;
  pname = "gamerack";

  package = inputs.self.packages.${system}.${pname};
  cfg = config.services.gamerack;
in {
  options.services.${pname} = {
    enable = lib.mkEnableOption "Game Collection Sync";

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = "Configuration settings.";
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "daily";
      description = "Interval for the ${pname} service to run.";
    };

    database = lib.mkOption {
      type = lib.types.path;
      description = "Full path to database file.";
    };

    environmentFiles = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [];
      example = ["/etc/${pname}/env" "/etc/${pname}/env-secret"];
      description = "List of environment files to be passed to the Game Collection Sync application.";
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      example = {
        MOBY_USERNAME = "myusername";
      };
      description = "Environment variables to pass to the ${pname} service.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd = {
      services.${pname} = {
        description = "Game Collection Sync Service";
        after = ["network.target"];
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          EnvironmentFile = lib.optional (cfg.environmentFiles != []) (lib.concatStringsSep " " cfg.environmentFiles);
          Environment = lib.mapAttrsToList (name: value: "${name}=${value}") cfg.environment;
          ExecStart = let
            jsonConfig = builtins.toJSON cfg.settings;
            jsonConfigFile = pkgs.writeText "config.yml" jsonConfig;
          in "${package}/bin/${pname} --database ${cfg.database} sync";
          # in "${pkgs.gamerack}/bin/gamerack --config <(${pkgs.yq}/bin/yq eval -P '${jsonConfigFile}/config.yml') sync";
          Restart = "on-failure";
        };
      };

      timers.${pname} = {
        description = "Game Collection Sync Timer";
        partOf = ["${pname}.service"];
        wantedBy = ["timers.target"];
        timerConfig.OnCalendar = cfg.interval;
      };
    };
  };
}
