{ lib, pkgs, buildPackages, common, buildModule }:

let
  fetchSource = common.fetchSource;
  waypipeSource = {
    source = "gitlab";
    owner = "mstoeckl";
    repo = "waypipe";
    tag = "v0.10.6";
    sha256 = "sha256-Tbd/yY90yb2+/ODYVL3SudHaJCGJKatZ9FuGM2uAX+8=";
  };
  src = fetchSource waypipeSource;
  buildFlags = [ "--target=aarch64-apple-ios" "--features=vulkan" ];
  patches = [];
in
pkgs.rustPlatform.buildRustPackage {
  pname = "waypipe";
  version = "v0.10.6";
  inherit src patches;
  cargoHash = "sha256-IUvXHLxrhc2Au57wsE53Q+NL1cZzFcaRG3HDV8s3xWw=";
  cargoLock = null;
  nativeBuildInputs = with buildPackages; [ pkg-config ];
  buildInputs = [];
  CARGO_BUILD_TARGET = "aarch64-apple-ios";
}
