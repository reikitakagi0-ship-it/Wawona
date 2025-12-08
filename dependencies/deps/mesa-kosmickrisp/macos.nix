{ lib, pkgs, common, buildModule }:

let
  fetchSource = common.fetchSource;
  mesaSource = {
    source = "gitlab";
    owner = "mesa";
    repo = "mesa";
    branch = "main";
    sha256 = "sha256-Kw5xL5RllnCBWvQiGK5pAb5KedJZy/Tt6rVYVbkobh8=";
  };
  src = fetchSource mesaSource;
  buildFlags = [
    "-Dvulkan-drivers=kosmickrisp"
    "-Dgallium-drivers="
    "-Dplatforms="
    "-Dglx=disabled"
    "-Degl=disabled"
    "-Dgbm=disabled"
    "-Dtools="
    "-Dvulkan-beta=true"
    "-Dbuildtype=release"
    "-Dglvnd=disabled"
    "-Dgallium-va=disabled"
  ];
  patches = [];
  getDeps = depNames:
    map (depName:
      if depName == "libclc" then pkgs.libclc
      else if depName == "zlib" then pkgs.zlib
      else if depName == "zstd" then pkgs.zstd
      else if depName == "expat" then pkgs.expat
      else if depName == "llvm" then pkgs.llvmPackages.llvm
      else throw "Unknown dependency: ${depName}"
    ) depNames;
  depInputs = getDeps [ "libclc" "zlib" "zstd" "expat" "llvm" ];
in
pkgs.stdenv.mkDerivation {
  name = "mesa-kosmickrisp-macos";
  inherit src patches;
  nativeBuildInputs = with pkgs; [
    meson ninja pkg-config
    (python3.withPackages (ps: with ps; [ setuptools pip packaging mako pyyaml ]))
    bison flex
  ];
  buildInputs = depInputs;
  configurePhase = ''
    runHook preConfigure
    meson setup build \
      --prefix=$out \
      --libdir=$out/lib \
      ${lib.concatMapStringsSep " \\\n  " (flag: flag) buildFlags}
    runHook postConfigure
  '';
  buildPhase = ''
    runHook preBuild
    meson compile -C build
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    meson install -C build
    runHook postInstall
  '';
}
