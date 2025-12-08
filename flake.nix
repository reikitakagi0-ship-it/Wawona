{
  description = "Wawona Multiplex Runner";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs";
  
  outputs = { self, nixpkgs }: let
    systems = [ "aarch64-darwin" ];
    forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
  in {
    packages = forAllSystems (system: let
      pkgs = import nixpkgs { 
        inherit system;
        config = {
          allowUnfree = true;
        };
      };
      
      # Import dependencies module
      depsModule = import ./dependencies/common/common.nix {
        lib = pkgs.lib;
        inherit pkgs;
      };
      
      # Import build module
      buildModule = import ./dependencies/build.nix {
        lib = pkgs.lib;
        inherit pkgs;
        stdenv = pkgs.stdenv;
        buildPackages = pkgs.buildPackages;
      };
      
      # Import Wawona build module
      # Filter source to exclude build artifacts and other files
      wawonaSrc = pkgs.lib.cleanSourceWith {
        src = ./.;
        filter = path: type:
          let
            baseName = baseNameOf path;
            relPath = pkgs.lib.removePrefix (toString ./. + "/") (toString path);
          in
            !(
              baseName == ".git" ||
              baseName == "build" ||
              baseName == "result" ||
              baseName == ".direnv" ||
              pkgs.lib.hasPrefix "result" baseName ||
              pkgs.lib.hasPrefix ".git" baseName
            );
      };
      
      wawonaBuildModule = {
        ios = pkgs.hello;
        macos = pkgs.hello;
        android = pkgs.hello;
      };
      
      # Get registry for building individual dependencies
      registry = depsModule.registry;
      
      # Build all dependencies for each platform
      iosDeps = buildModule.ios;
      macosDeps = buildModule.macos;
      androidDeps = buildModule.android;
      
      # Create individual dependency packages for each platform
      # Format: <dependency-name>-<platform>
      dependencyPackages = let
        # Helper to create packages for a platform
        createPlatformPackages = platform: deps:
          pkgs.lib.mapAttrs' (name: pkg: {
            name = "${name}-${platform}";
            value = pkg;
          }) deps;
        
        iosPkgs = createPlatformPackages "ios" iosDeps;
        macosPkgs = createPlatformPackages "macos" macosDeps;
        androidPkgs = createPlatformPackages "android" androidDeps;
        
        # libwayland is handled directly in platform dispatchers, not via registry
        directPkgs = {
          "libwayland-ios" = buildModule.buildForIOS "libwayland" {};
          "libwayland-macos" = buildModule.buildForMacOS "libwayland" {};
          "libwayland-android" = buildModule.buildForAndroid "libwayland" {};
          "expat-ios" = buildModule.buildForIOS "expat" {};
          "expat-macos" = buildModule.buildForMacOS "expat" {};
          "expat-android" = buildModule.buildForAndroid "expat" {};
          "libffi-ios" = buildModule.buildForIOS "libffi" {};
          "libffi-macos" = buildModule.buildForMacOS "libffi" {};
          "libffi-android" = buildModule.buildForAndroid "libffi" {};
          "libxml2-ios" = buildModule.buildForIOS "libxml2" {};
          "libxml2-macos" = buildModule.buildForMacOS "libxml2" {};
          "libxml2-android" = buildModule.buildForAndroid "libxml2" {};
          "waypipe-ios" = buildModule.buildForIOS "waypipe" {};
          "waypipe-macos" = buildModule.buildForMacOS "waypipe" {};
          "waypipe-android" = buildModule.buildForAndroid "waypipe" {};
          "mesa-kosmickrisp-ios" = buildModule.buildForIOS "mesa-kosmickrisp" {};
          "mesa-kosmickrisp-macos" = buildModule.buildForMacOS "mesa-kosmickrisp" {};
          "epoll-shim-ios" = buildModule.buildForIOS "epoll-shim" {};
          "epoll-shim-macos" = buildModule.buildForMacOS "epoll-shim" {};
        };
      in
        iosPkgs // macosPkgs // androidPkgs // directPkgs;
      
      # Wrapper script to run Nix build and show dialog on exit
      wawonaWrapper = pkgs.writeShellScriptBin "wawona-wrapper" ''
        TARGET=$1
        LOGFILE="build/$TARGET.log"
        mkdir -p build
        
        # Map target names to Nix package names
        case "$TARGET" in
          ios-compositor)
            NIX_PKG="wawona-ios"
            ;;
          macos-compositor)
            NIX_PKG="wawona-macos"
            ;;
          android-compositor)
            NIX_PKG="wawona-android"
            ;;
          *)
            echo "Unknown target: $TARGET"
            exit 1
            ;;
        esac
        
        # Run nix build and capture output (tee to log and stdout)
        # We use a subshell to capture exit code of nix build, not tee
        set +e
        ( nix build --show-trace .#"$NIX_PKG" 2>&1; echo $? > build/"$TARGET".exitcode ) | tee "$LOGFILE"
        EXIT_CODE=$(cat build/"$TARGET".exitcode)
        rm build/"$TARGET".exitcode
        set -e
        
        while true; do
            if [ "$EXIT_CODE" -eq 0 ]; then
                MSG="Build '$TARGET' SUCCEEDED."
            else
                MSG="Build '$TARGET' FAILED (Exit Code: $EXIT_CODE)."
            fi
            
            CHOICE=$(dialog --clear --title "Wawona Build: $TARGET" \
                --menu "$MSG\nSelect an action:" 16 60 5 \
                "1" "View Logs (less)" \
                "2" "Open Logs (Default App)" \
                "3" "Reveal Logs in Finder" \
                "4" "Copy Log Here" \
                "5" "Exit Pane" \
                2>&1 >/dev/tty)
            
            case $CHOICE in
                1)
                    less -R "$LOGFILE"
                    ;;
                2)
                    open "$LOGFILE"
                    ;;
                3)
                    open -R "$LOGFILE"
                    ;;
                4)
                    cp "$LOGFILE" "./$TARGET.log"
                    dialog --msgbox "Log copied to ./$TARGET.log" 6 40
                    ;;
                5)
                    break
                    ;;
                *)
                    break
                    ;;
            esac
        done
      '';

      wawonaBuildInputs = with pkgs; [
        cmake meson ninja pkg-config
        autoconf automake libtool texinfo
        git python3 direnv gnumake patch
        bison flex shaderc mesa
        tmux dialog
      ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
        # Xcode tools are system-provided usually
      ];
    in {
      default = pkgs.writeShellApplication {
        name = "wawona-multiplex";
        runtimeInputs = wawonaBuildInputs ++ [ wawonaWrapper ];
        text = ''
          set -euo pipefail
          session="wawona-build"
          if tmux has-session -t "$session" 2>/dev/null; then
            tmux kill-session -t "$session"
          fi
          
          # Start session (pane 0) - ios-compositor
          tmux new-session -d -s "$session" "wawona-wrapper ios-compositor"
          
          # Split horizontally (pane 1) - android-compositor
          tmux split-window -h -t "$session":0
          tmux send-keys -t "$session":0.1 "wawona-wrapper android-compositor" C-m
          
          # Split pane 1 vertically (pane 2) - macos-compositor
          tmux split-window -v -t "$session":0.1
          tmux send-keys -t "$session":0.2 "wawona-wrapper macos-compositor" C-m
          
          # Select first pane
          tmux select-pane -t "$session":0.0
          
          # Attach
          tmux attach-session -t "$session"
        '';
      };
      
      # Add Wawona build packages
      wawona-ios = wawonaBuildModule.ios;
      wawona-macos = wawonaBuildModule.macos;
      wawona-android = wawonaBuildModule.android;
      
      # Add dependency packages
      # Format: <dependency-name>-<platform> (e.g., wayland-ios, mesa-kosmickrisp-macos)
    } // dependencyPackages);
    
    apps = forAllSystems (system: {
      default = {
        type = "app";
        program = "${self.packages.${system}.default}/bin/wawona-multiplex";
      };
    });
    
    devShells = forAllSystems (system: let
      pkgs = import nixpkgs { inherit system; };
    in {
      default = pkgs.mkShell {
        name = "wawona-dev";
        buildInputs = with pkgs; [
          cmake
          meson
          ninja
          pkg-config
          autoconf
          automake
          libtool
          texinfo
          git
          python3
          direnv
          gnumake
          patch
          bison
          flex
          shaderc
          mesa
          dialog
        ];
        shellHook = ''
            echo "🔨 Wawona Development Environment"
            echo "Run 'nix run' to build Wawona for all platforms (iOS, macOS, Android)"
            echo ""
            echo "Available builds:"
            echo "  - nix build .#wawona-ios      (iOS)"
            echo "  - nix build .#wawona-macos   (macOS)"
            echo "  - nix build .#wawona-android (Android)"
            echo ""
            echo "Dependencies are automatically built as needed."
        '';
      };
    });
  };
}
