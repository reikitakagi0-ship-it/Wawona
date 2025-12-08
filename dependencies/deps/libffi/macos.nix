{ lib, pkgs, common }:

let
  fetchSource = common.fetchSource;
  libffiSource = {
    source = "github";
    owner = "libffi";
    repo = "libffi";
    tag = "v3.5.2";
    sha256 = "sha256-tvNdhpUnOvWoC5bpezUJv+EScnowhURI7XEtYF/EnQw=";
  };
  src = fetchSource libffiSource;
  buildFlags = [];
  patches = [];
in
pkgs.stdenv.mkDerivation {
  name = "libffi-macos";
  inherit src patches;
  nativeBuildInputs = with pkgs; [ autoconf automake libtool pkg-config apple-sdk_26 ];
  buildInputs = [];
  preConfigure = ''
    MACOS_SDK="${pkgs.apple-sdk_26}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
    export SDKROOT="$MACOS_SDK"
    export MACOSX_DEPLOYMENT_TARGET="26.0"
    export CFLAGS="-isysroot $MACOS_SDK -mmacosx-version-min=26.0 ''${NIX_CFLAGS_COMPILE:-}"
    export LDFLAGS="-isysroot $MACOS_SDK -mmacosx-version-min=26.0 ''${NIX_LDFLAGS:-}"
  '';
  configureFlags = buildFlags;
}
