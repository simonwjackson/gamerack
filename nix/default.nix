{pkgs, ...}:
pkgs.resholve.mkDerivation rec {
  pname = "gamerack";
  version = "0.1.0";

  src = ../src;

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    mkdir -p $out/share/man/man1
    ${pkgs.pandoc}/bin/pandoc -s -t man ./gamerack.1.md -o $out/share/man/man1/gamerack.1

    find ./bin -type f -exec install -vDm 755 {} $out/{} \;
    chmod +x $out/bin/*.sh
  '';

  solutions = {
    default = {
      scripts = [
        "bin/gamerack"
        "bin/*.sh"
      ];
      interpreter = "${pkgs.bash}/bin/bash";
      inputs = with pkgs; [
        "${placeholder "out"}/bin"

        bash
        pup
        bc
        coreutils
        curl
        docopts
        gnugrep
        gnused
        gawk
        jq
        miller
        yq
      ];
      execer = [
        "cannot:${pkgs.docopts}/bin/docopts"
        "cannot:${pkgs.docopts}/bin/docopts.sh"
        "cannot:${pkgs.miller}/bin/mlr"
        "cannot:${pkgs.pup}/bin/pup"
        "cannot:${pkgs.wget}/bin/wget"
        "cannot:${pkgs.yq}/bin/yq"
      ];
    };
  };
}
