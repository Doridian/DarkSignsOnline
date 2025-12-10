{
  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        gitrev = self.rev or "${self.dirtyRev}-dirty";
        package = pkgs.stdenvNoCC.mkDerivation {
          name = "darksignsonline-server";
          version = "1.0.0";
          src = ./server/www;
          installPhase = ''
            mkdir -p "$out/var/www"
            cp -r "$src" "$out/var/www/darksignsonline"
            chmod 700 "$out/var/www/darksignsonline/api"
            echo '${gitrev}' > "$out/var/www/darksignsonline/api/gitrev.txt"
          '';
        };
      in
      {
        packages.default = package;
        packages.darksignsonline-server = package;
      }
    );
}
