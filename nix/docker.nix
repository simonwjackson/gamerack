{
  pkgs,
  gamerack,
}:
pkgs.dockerTools.buildLayeredImage {
  name = "gamerack";
  tag = "latest";
  config = {
    Cmd = ["${gamerack}/bin/gamerack"];
  };
  contents = [
    gamerack
  ];
}
