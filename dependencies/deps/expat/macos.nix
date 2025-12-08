{ lib, pkgs, common }:

let
  fetchSource = common.fetchSource;
  expatSource = {
    source = "github";
    owner = "libexpat";
    repo = "libexpat";
    tag = "R_2_7_3";
    sha256 = "sha256-dDxnAJsj515vr9+j2Uqa9E+bB+teIBfsnrexppBtdXg=";
  };
  src = fetchSource expatSource;
  buildFlags = [];
  patches = [];
in
pkgs.stdenv.mkDerivation {
  name = "expat-macos";
  inherit src patches;
  nativeBuildInputs = with pkgs; [ cmake pkg-config ];
  buildInputs = [];
  cmakeFlags = buildFlags;
}
