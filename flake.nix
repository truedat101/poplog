{
  description = "Poplog -- Pop-11, Prolog, Common Lisp and ML (AArch64/x86-64, Linux/macOS)";

  # 25.05 (not 24.05): SDL3 (sdl3 3.2.20) only lands in nixpkgs from 25.05,
  # and the experimental Linux graphics backend needs it.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
      forAll = f: nixpkgs.lib.genAttrs systems (system:
        f nixpkgs.legacyPackages.${system} system);

      # The runnable language front-ends the package installs into bin/.
      progs = [ "pop11" "basepop11" "clisp" "prolog" "pml" "ved" ];

      # ImGui source for the experimental graphics build (the in-tree
      # pop/extern/imgui/ is gitignored; the sandbox has no network).
      imguiSrc = pkgs: pkgs.fetchFromGitHub {
        owner = "ocornut"; repo = "imgui"; rev = "v1.92.2";
        hash = "sha256-ZEGOHrkjIr4ZuUodDxuOCzbHPZjJsmDNYoZ8m4iZQiE=";
      };
    in {
      packages = forAll (pkgs: system: rec {
        poplog = pkgs.callPackage ./nix/poplog.nix {
          inherit self system;
          sigtool = if pkgs.stdenv.isDarwin
                    then (pkgs.darwin.sigtool or null) else null;
        };
        default = poplog;
      } // nixpkgs.lib.optionalAttrs (!pkgs.stdenv.isDarwin) {
        # experimental native graphics (SDL3 + OpenGL3), Linux only for now
        poplog-gfx = pkgs.callPackage ./nix/poplog.nix {
          inherit self system;
          withGraphics = true;
          sdl3 = pkgs.sdl3; libGL = pkgs.libGL;
          inherit (pkgs) pkg-config;
          imgui = imguiSrc pkgs;
        };
      });

      # `nix run .#pop11`, `.#prolog`, `.#clisp`, `.#pml`, `.#ved`;
      # bare `nix run` starts the Pop-11 REPL.
      apps = forAll (pkgs: system:
        let poplog = self.packages.${system}.poplog;
        in (nixpkgs.lib.genAttrs progs (p: {
              type = "app";
              program = "${poplog}/bin/${p}";
            })) // {
          default = { type = "app"; program = "${poplog}/bin/pop11"; };
        });

      # `nix shell .#poplog` puts all the front-ends on PATH; `nix develop`
      # gives the same plus a banner for hacking on Poplog code.
      devShells = forAll (pkgs: system:
        let poplog = self.packages.${system}.poplog;
        in {
          default = pkgs.mkShell {
            packages = [ poplog ];
            shellHook = ''
              echo "Poplog dev shell -- pop11 / clisp / prolog / pml / ved on PATH"
              echo "  \$usepop = ${poplog}/poplog/pop"
            '';
          };
        });
    };
}
