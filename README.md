# Usage as a flake

[![FlakeHub](https://img.shields.io/endpoint?url=https://flakehub.com/f/simonwjackson/gamerack/badge)](https://flakehub.com/flake/simonwjackson/gamerack)

Add gamerack to your `flake.nix`:

```nix
{
  inputs.gamerack.url = "https://flakehub.com/f/simonwjackson/gamerack/*.tar.gz";

  outputs = { self, gamerack }: {
    # Use in your outputs
  };
}
```
