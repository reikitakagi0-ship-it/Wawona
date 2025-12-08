{ lib, pkgs, common }:

let
  fetchSource = common.fetchSource;
  libxml2Source = {
    source = "gitlab-gnome";
    owner = "GNOME";
    repo = "libxml2";
    rev = "v2.14.0";
    sha256 = "sha256-SFDNj4QPPqZUGLx4lfaUzHn0G/HhvWWXWCFoekD9lYM=";
  };
  src = fetchSource libxml2Source;
  buildFlags = [];
  patches = [];
in
pkgs.stdenv.mkDerivation {
  name = "libxml2-macos";
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
