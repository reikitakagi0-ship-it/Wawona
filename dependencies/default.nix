# Minimal GitHub dependency tracking module
# 
# This module provides a simple way to track and reference GitHub dependencies
# in your Nix flake inputs, with support for building for iOS, macOS, and Android.

{ lib, pkgs ? null }:

let
  # Import the dependency registry
  registry = import ./registry.nix;
  
  # Helper function to get source type (github or gitlab)
  getSource = entry: entry.source or "github";
  
  # Helper function to convert registry entries to flake input format
  toFlakeInput = entry:
    let
      source = getSource entry;
      baseUrl = if source == "gitlab" then "gitlab:${entry.owner}/${entry.repo}" else "github:${entry.owner}/${entry.repo}";
    in
    if lib.hasAttr "rev" entry then
      {
        url = baseUrl;
        inherit (entry) rev;
      } // lib.optionalAttrs (lib.hasAttr "sha256" entry) {
        inherit (entry) sha256;
      }
    else if lib.hasAttr "tag" entry then
      {
        url = "${baseUrl}/${entry.tag}";
      } // lib.optionalAttrs (lib.hasAttr "sha256" entry) {
        inherit (entry) sha256;
      }
    else if lib.hasAttr "branch" entry then
      {
        url = baseUrl;
        inherit (entry) branch;
      } // lib.optionalAttrs (lib.hasAttr "sha256" entry) {
        inherit (entry) sha256;
      }
    else
      {
        url = baseUrl;
      };
  
  # Convert registry to flake inputs format
  inputs = lib.mapAttrs (_: toFlakeInput) registry;
  
  # Get platforms for a dependency (defaults to all platforms)
  getPlatforms = entry:
    if lib.hasAttr "platforms" entry then entry.platforms
    else [ "ios" "macos" "android" ];
  
  # Filter dependencies by platform
  forPlatform = platform:
    lib.filterAttrs (_: entry:
      lib.elem platform (getPlatforms entry)
    ) registry;
  
  # Get dependencies that need to be built for a specific platform
  getDependenciesForPlatform = platform:
    lib.mapAttrsToList (name: entry: {
      inherit name;
      inherit (entry) owner repo buildSystem;
      platforms = getPlatforms entry;
      buildFlags = entry.buildFlags.${platform} or [];
      patches = entry.patches.${platform} or [];
    }) (forPlatform platform);
in
{
  # The registry of all dependencies
  inherit registry;
  
  # Flake inputs ready to use in flake.nix
  inherit inputs;
  
  # Helper to get a specific dependency
  get = name: registry.${name} or null;
  
  # Helper to get flake input for a specific dependency
  getInput = name: inputs.${name} or null;
  
  # Get all dependencies for a specific platform
  forPlatform = platform: forPlatform platform;
  
  # Get list of dependencies to build for a platform
  getDependenciesForPlatform = platform: getDependenciesForPlatform platform;
  
  # Check if a dependency should be built for a platform
  shouldBuildForPlatform = name: platform:
    let dep = registry.${name} or null;
    in dep != null && lib.elem platform (getPlatforms dep);
  
  # Get build configuration for a dependency on a platform
  getBuildConfig = name: platform:
    let dep = registry.${name} or null;
    in if dep == null then null
    else {
      inherit (dep) owner repo buildSystem;
      source = getSource dep;
      buildFlags = dep.buildFlags.${platform} or [];
      patches = dep.patches.${platform} or [];
      platforms = getPlatforms dep;
    };
}
