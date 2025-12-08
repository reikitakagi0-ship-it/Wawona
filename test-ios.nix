let
  pkgs = import <nixpkgs> {};
in
  import ./dependencies/utils/test-ios-toolchain.nix {
    inherit (pkgs) lib pkgs;
    buildPackages = pkgs;
  }
