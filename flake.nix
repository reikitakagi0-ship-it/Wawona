{
  description = "Wawona Multiplex Runner";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs";
  
  outputs = { self, nixpkgs }: let
    systems = [ "aarch64-darwin" ];
    forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
  in {
    packages = forAllSystems (system: let
      pkgs = import nixpkgs { inherit system; };
      
      # Import dependencies module
      depsModule = import ./dependencies/default.nix {
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
      in
        iosPkgs // macosPkgs // androidPkgs;
      
      # Wrapper script to run make target and show dialog on exit
      wawonaWrapper = pkgs.writeShellScriptBin "wawona-wrapper" ''
        TARGET=$1
        LOGFILE="build/$TARGET.log"
        mkdir -p build
        
        # Run make and capture output (tee to log and stdout)
        # We use a subshell to capture exit code of make, not tee
        set +e
        ( make "$TARGET" 2>&1; echo $? > build/"$TARGET".exitcode ) | tee "$LOGFILE"
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
            echo "Run 'nix run' to start the multiplexed build."
        '';
      };
    });
  };
}
