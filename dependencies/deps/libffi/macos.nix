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
  nativeBuildInputs = with pkgs; [ autoconf automake libtool pkg-config ];
  buildInputs = [];
  configureFlags = buildFlags;
}
