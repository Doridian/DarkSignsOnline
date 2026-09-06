{
  description = "Dark Signs Online: the PHP game server and the browser client";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
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
        inherit (pkgs) lib;

        # The only identity a build has. Deployments come from a commit, so
        # the commit is what the site's footer links to.
        gitrev = self.rev or self.dirtyRev or "unknown";

        # wasm-bindgen refuses a module whose schema was written by a
        # different version of itself, so the CLI is built from the version
        # the crate is locked to rather than from whatever nixpkgs happens to
        # ship. Bumping the crate changes the two hashes below, and nix says
        # what they became.
        wasmBindgen =
          let
            lock = builtins.fromTOML (builtins.readFile ./client/Cargo.lock);
            version = (lib.findFirst (p: p.name == "wasm-bindgen") null lock.package).version;
            src = pkgs.fetchCrate {
              pname = "wasm-bindgen-cli";
              inherit version;
              hash = "sha256-a7lcXJnnZkYReja+iUO7NqqrWyv3toxnUgQb8s4IS5s=";
            };
          in
          pkgs.buildWasmBindgenCli {
            inherit src;
            cargoDeps = pkgs.rustPlatform.fetchCargoVendor {
              inherit src;
              inherit (src) pname version;
              hash = "sha256-R1Tas33Ursy8kqsxguAkG0ZhNed2n5uFTAhw1l2qlLY=";
            };
          };

        # typescript, from package-lock.json. No hash to keep in step: the
        # lock file's own integrity fields are what fetches each tarball.
        nodeModules = pkgs.importNpmLock.buildNodeModules {
          npmRoot = ./client/web;
          inherit (pkgs) nodejs;
        };

        server = pkgs.stdenvNoCC.mkDerivation {
          name = "darksignsonline-server";
          src = ./server/www;
          dontUnpack = true;
          installPhase = ''
            runHook preInstall
            mkdir -p "$out/var/www"
            cp -r "$src" "$out/var/www/darksignsonline"
            chmod -R u+w "$out/var/www/darksignsonline"
            cp ${./LICENSE} "$out/var/www/darksignsonline/LICENSE"
            echo '${gitrev}' > "$out/var/www/darksignsonline/api/gitrev.txt"
            runHook postInstall
          '';
        };

        client = pkgs.stdenv.mkDerivation {
          name = "darksignsonline-client";
          # Nix takes the git tree, so everything `build.sh` generates --
          # `target`, `node_modules`, `www/pkg`, `www/scripts`, `dist`, the
          # JavaScript beside the TypeScript -- is already left out by the
          # .gitignore that names it.
          src = ./client;

          cargoDeps = pkgs.rustPlatform.importCargoLock { lockFile = ./client/Cargo.lock; };

          nativeBuildInputs = [
            pkgs.rustPlatform.cargoSetupHook
            pkgs.cargo
            pkgs.rustc
            wasmBindgen
            pkgs.nodejs
            # zstd-sys compiles C, and for wasm32 only clang can. Unwrapped,
            # because the wrappers hand it the host's target and includes.
            pkgs.llvmPackages.clang-unwrapped
            pkgs.llvmPackages.bintools-unwrapped
          ];

          env = {
            CC_wasm32_unknown_unknown = "${pkgs.llvmPackages.clang-unwrapped}/bin/clang";
            AR_wasm32_unknown_unknown = "${pkgs.llvmPackages.bintools-unwrapped}/bin/llvm-ar";
            CARGO_NET_OFFLINE = "true";
          };

          buildPhase = ''
            runHook preBuild
            export HOME="$NIX_BUILD_TOP/home"
            mkdir -p "$HOME"
            ln -s ${nodeModules}/node_modules web/node_modules
            bash web/build.sh
            runHook postBuild
          '';

          # The page's own checks: the third TypeScript project (the
          # scripts and the test, which the browser projects do not
          # cover) and the editor's highlighting and indenting rules.
          doCheck = true;
          checkPhase = ''
            runHook preCheck
            npm --prefix web run --silent check
            npm --prefix web test
            runHook postCheck
          '';

          # web/dist, not web/www: the served copy, which `stamp.ts` writes
          # from what the build has produced. It holds what the page loads and
          # nothing else -- no sources, no intermediates -- and every asset in
          # it is named for the hash of its contents.
          installPhase = ''
            runHook preInstall
            mkdir -p "$out/var/www/darksignsonline"
            cp -r web/dist/. "$out/var/www/darksignsonline/"
            runHook postInstall
          '';
        };

        # One web root holding both. The client gets `game/` to itself: the
        # page is that directory's `index.html`, so `/game` (which nginx
        # redirects to `/game/`) is the whole address a player needs, and
        # every asset the client ships sits under the same prefix rather than
        # scattered through the site's root.
        #
        # The client is static, all of it. The two headers that make the page
        # cross-origin isolated -- without which the browser withholds
        # SharedArrayBuffer and the workers cannot block waiting for input --
        # come from nginx, which sends them for everything under `/game/`.
        # See `server.conf` for why it has to be everything and not just the
        # page. The page addresses its assets relatively, so a document at
        # `/game/` resolves `./main.js` to `/game/main.js` with nothing to
        # rewrite.
        site = pkgs.runCommand "darksignsonline" { } ''
          root="$out/var/www/darksignsonline"
          mkdir -p "$out/var/www"
          cp -r --no-preserve=mode,ownership ${server}/var/www/darksignsonline "$root"
          mkdir -p "$root/game"
          cp -r --no-preserve=mode,ownership ${client}/var/www/darksignsonline/. "$root/game/"
        '';
      in
      {
        packages = {
          default = site;
          darksignsonline = site;
          darksignsonline-server = server;
          darksignsonline-client = client;
        };

        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.cargo
            pkgs.rustc
            pkgs.clippy
            pkgs.rustfmt
            wasmBindgen
            pkgs.nodejs
            pkgs.llvmPackages.clang-unwrapped
            pkgs.llvmPackages.bintools-unwrapped
          ];
          env = {
            CC_wasm32_unknown_unknown = "${pkgs.llvmPackages.clang-unwrapped}/bin/clang";
            AR_wasm32_unknown_unknown = "${pkgs.llvmPackages.bintools-unwrapped}/bin/llvm-ar";
          };
        };
      }
    );
}
