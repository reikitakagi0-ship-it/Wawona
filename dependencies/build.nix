{ lib, pkgs, stdenv, buildPackages }:

let
  common = import ./common/common.nix { inherit lib pkgs; };
  androidModuleSelf = rec {
    buildForAndroid = name: entry:
      if name == "libwayland" then
        (import ./deps/libwayland/android.nix) { inherit lib pkgs buildPackages common; buildModule = androidModuleSelf; }
      else if name == "expat" then
        (import ./deps/expat/android.nix) { inherit lib pkgs buildPackages common; buildModule = androidModuleSelf; }
      else if name == "libffi" then
        (import ./deps/libffi/android.nix) { inherit lib pkgs buildPackages common; buildModule = androidModuleSelf; }
      else if name == "libxml2" then
        (import ./deps/libxml2/android.nix) { inherit lib pkgs buildPackages common; buildModule = androidModuleSelf; }
      else if name == "waypipe" then
        (import ./deps/waypipe/android.nix) { inherit lib pkgs buildPackages common; buildModule = androidModuleSelf; }
      else
        (import ./platforms/android.nix { inherit lib pkgs buildPackages common; buildModule = androidModuleSelf; }).buildForAndroid name entry;
  };
  androidModule = androidModuleSelf;
  iosModuleSelf = rec {
    buildForIOS = name: entry:
      if name == "libwayland" then
        (import ./deps/libwayland/ios.nix) { inherit lib pkgs buildPackages common; buildModule = iosModuleSelf; }
      else if name == "expat" then
        (import ./deps/expat/ios.nix) { inherit lib pkgs buildPackages common; buildModule = iosModuleSelf; }
      else if name == "libffi" then
        (import ./deps/libffi/ios.nix) { inherit lib pkgs buildPackages common; buildModule = iosModuleSelf; }
      else if name == "libxml2" then
        (import ./deps/libxml2/ios.nix) { inherit lib pkgs buildPackages common; buildModule = iosModuleSelf; }
      else if name == "waypipe" then
        (import ./deps/waypipe/ios.nix) { inherit lib pkgs buildPackages common; buildModule = iosModuleSelf; }
      else if name == "mesa-kosmickrisp" then
        (import ./deps/mesa-kosmickrisp/ios.nix) { inherit lib pkgs buildPackages common; buildModule = iosModuleSelf; }
      else if name == "epoll-shim" then
        (import ./deps/epoll-shim/ios.nix) { inherit lib pkgs buildPackages common; buildModule = iosModuleSelf; }
      else
        (import ./platforms/ios.nix { inherit lib pkgs buildPackages common; buildModule = iosModuleSelf; }).buildForIOS name entry;
  };
  iosModule = iosModuleSelf;
  macosModuleSelf = rec {
    buildForMacOS = name: entry:
      if name == "libwayland" then
        (import ./deps/libwayland/macos.nix) { inherit lib pkgs common; buildModule = macosModuleSelf; }
      else if name == "expat" then
        (import ./deps/expat/macos.nix) { inherit lib pkgs common; }
      else if name == "libffi" then
        (import ./deps/libffi/macos.nix) { inherit lib pkgs common; }
      else if name == "libxml2" then
        (import ./deps/libxml2/macos.nix) { inherit lib pkgs common; }
      else if name == "epoll-shim" then
        (import ./deps/epoll-shim/macos.nix) { inherit lib pkgs common; buildModule = macosModuleSelf; }
      else if name == "waypipe" then
        (import ./deps/waypipe/macos.nix) { inherit lib pkgs common; buildModule = macosModuleSelf; }
      else if name == "mesa-kosmickrisp" then
        (import ./deps/mesa-kosmickrisp/macos.nix) { inherit lib pkgs common; buildModule = macosModuleSelf; }
      else
        (import ./platforms/macos.nix { inherit lib pkgs common; buildModule = macosModuleSelf; }).buildForMacOS name entry;
  };
  macosModule = macosModuleSelf;
  registry = common.registry;
  buildAllForPlatform = platform:
    let
      filteredRegistry = lib.filterAttrs (_: entry:
        let platforms = entry.platforms or [ "ios" "macos" "android" ];
        in lib.elem platform platforms
      ) registry;
      directPkgs = if platform == "ios" then {
        libwayland = iosModule.buildForIOS "libwayland" {};
        expat = iosModule.buildForIOS "expat" {};
        libffi = iosModule.buildForIOS "libffi" {};
        libxml2 = iosModule.buildForIOS "libxml2" {};
        waypipe = iosModule.buildForIOS "waypipe" {};
        "mesa-kosmickrisp" = iosModule.buildForIOS "mesa-kosmickrisp" {};
        "epoll-shim" = iosModule.buildForIOS "epoll-shim" {};
      } else if platform == "macos" then {
        libwayland = macosModule.buildForMacOS "libwayland" {};
        expat = macosModule.buildForMacOS "expat" {};
        libffi = macosModule.buildForMacOS "libffi" {};
        libxml2 = macosModule.buildForMacOS "libxml2" {};
        waypipe = macosModule.buildForMacOS "waypipe" {};
        "mesa-kosmickrisp" = macosModule.buildForMacOS "mesa-kosmickrisp" {};
        "epoll-shim" = macosModule.buildForMacOS "epoll-shim" {};
      } else if platform == "android" then {
        libwayland = androidModule.buildForAndroid "libwayland" {};
        expat = androidModule.buildForAndroid "expat" {};
        libffi = androidModule.buildForAndroid "libffi" {};
        libxml2 = androidModule.buildForAndroid "libxml2" {};
        waypipe = androidModule.buildForAndroid "waypipe" {};
      } else {};
    in
      lib.mapAttrs (name: entry:
        if platform == "ios" then iosModule.buildForIOS name entry
        else if platform == "macos" then macosModule.buildForMacOS name entry
        else if platform == "android" then androidModule.buildForAndroid name entry
        else throw "Unknown platform: ${platform}"
      ) filteredRegistry // directPkgs;
in
{
  buildForIOS = iosModuleSelf.buildForIOS;
  buildForMacOS = macosModuleSelf.buildForMacOS;
  buildForAndroid = androidModule.buildForAndroid;
  buildAllForPlatform = buildAllForPlatform;
  ios = buildAllForPlatform "ios";
  macos = buildAllForPlatform "macos";
  android = buildAllForPlatform "android";
}
