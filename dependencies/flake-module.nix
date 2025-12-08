# Flake module for dependencies
#
# This module can be imported into your flake.nix to automatically
# set up dependency inputs and build outputs for iOS, macOS, and Android.

{ self, lib, ... }:

{
  # Add dependency inputs to flake inputs
  inputs = let
    deps = import ./default.nix { lib = (import <nixpkgs> {}).lib; };
  in deps.inputs;
  
  # Add dependency packages to outputs
  outputs = { self, nixpkgs, ... } @ inputs: let
    pkgs = import nixpkgs { system = "aarch64-darwin"; };
    deps = import ./default.nix { lib = pkgs.lib; inherit pkgs; };
  in {
    # Example: packages for each platform
    # packages.aarch64-darwin = {
    #   ios-deps = import ./build.nix {
    #     inherit (pkgs) lib;
    #     inherit pkgs stdenv buildPackages;
    #   };
    # };
  };
}
