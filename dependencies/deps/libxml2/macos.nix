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
  nativeBuildInputs = with pkgs; [ autoconf automake libtool pkg-config ];
  buildInputs = [];
  configureFlags = buildFlags;
}
