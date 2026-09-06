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
          # `target`, `node_modules`, `www/pkg`, `www/scripts`, the
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

          installPhase = ''
            runHook preInstall
            mkdir -p "$out/var/www/darksignsonline"
            cp -r web/www/. "$out/var/www/darksignsonline/"
            rm -f "$out/var/www/darksignsonline/.gitignore"
            # The TypeScript beside the JavaScript it compiled to, and the
            # types wasm-bindgen emits for it. Neither is served.
            find "$out/var/www/darksignsonline" -name '*.ts' -delete
            runHook postInstall
          '';
        };

        # What turns the built `index.html` into `game.php`: the two headers
        # that make the page cross-origin isolated, without which the browser
        # withholds SharedArrayBuffer and the client's workers cannot block
        # waiting for input. PHP eats the newline right after `?>`, so the
        # page still begins with its doctype.
        #
        # They are sent by the page itself rather than by the web server, so
        # that the page carries its own requirement wherever it is served
        # from. Its worker is the exception: a dedicated worker's own response
        # has to repeat `require-corp` or the browser refuses the script, and
        # `worker.js` is a static file, so `server.conf` says that one.
        gamePhpHeaders = pkgs.writeText "game-headers.php" ''
          <?php
          header('Cross-Origin-Opener-Policy: same-origin');
          header('Cross-Origin-Embedder-Policy: require-corp');
          ?>
        '';

        # One web root holding both. The client's page becomes `game.php` --
        # under a `.php` name for consistency with `forgot_password.php` and
        # the rest of the site, and now genuinely PHP: the prologue above and
        # then the built page, unchanged.
        #
        # Its assets stay at the root beside it because the page addresses
        # them relatively: a document at `/game.php` resolves `./main.js` to
        # `/main.js`.
        site = pkgs.runCommand "darksignsonline" { } ''
          root="$out/var/www/darksignsonline"
          mkdir -p "$out/var/www"
          cp -r --no-preserve=mode,ownership ${server}/var/www/darksignsonline "$root"
          cp -r --no-preserve=mode,ownership ${client}/var/www/darksignsonline/. "$root/"
          cat ${gamePhpHeaders} "$root/index.html" > "$root/game.php"
          rm "$root/index.html"
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
