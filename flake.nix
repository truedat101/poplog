{
  description = "Poplog -- Pop-11, Prolog, Common Lisp and ML (AArch64/x86-64, Linux/macOS)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
      forAll = f: nixpkgs.lib.genAttrs systems (system:
        f nixpkgs.legacyPackages.${system} system);
    in {
      packages = forAll (pkgs: system: rec {
        poplog = pkgs.callPackage ./nix/poplog.nix {
          inherit self system;
          sigtool = if pkgs.stdenv.isDarwin
                    then (pkgs.darwin.sigtool or null) else null;
        };
        default = poplog;
      });
    };
}
