{
  description = "Build a cargo workspace";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";

    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.rust-analyzer-src.follows = "";
    };

    flake-utils.url = "github:numtide/flake-utils";

    advisory-db = {
      url = "github:rustsec/advisory-db";
      flake = false;
    };
  };


  outputs = { self, nixpkgs, crane, fenix, flake-utils, advisory-db, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkg_libs = libs :
            pkgs.lib.strings.concatMapStringsSep ":" (l: "${l.dev}/lib/pkgconfig/") libs;
        overlays = [ fenix.overlays.default ];
        pkgs = import nixpkgs {
          inherit system overlays;
        };

        inherit (pkgs) lib;

        craneLib = crane.mkLib pkgs;
        src = craneLib.cleanCargoSource ./.;

        libraries = with pkgs; [libsoup openssl webkitgtk openconnect];

        # Common arguments can be set here to avoid repeating them later
        commonArgs = {
          inherit src;

          buildInputs = [
            pkgs.pkg-config
            pkgs.gcc
          ] ++ libraries;

          PKG_CONFIG_PATH = with pkgs; pkg_libs libraries;
          OPENSSL_NO_VENDOR = 1;
        };

        rustPackages = fenix.packages.${system}.complete.withComponents [
            "cargo"
            "llvm-tools"
            "rustc"
          ];

        # Build *just* the cargo dependencies (of the entire workspace),
        # so we can reuse all of that work (e.g. via cachix) when running in CI
        # It is *highly* recommended to use something like cargo-hakari to avoid
        # cache misses when building individual top-level-crates
        cargoArtifacts = craneLib.buildDepsOnly (commonArgs // {pname = "cargoArtifacts";});

        individualCrateArgs = commonArgs // {
          inherit cargoArtifacts;
          # NB: we disable tests since we'll run them all via cargo-nextest
          doCheck = false;
        };

        fileSetForCrate = lib.fileset.toSource {
          root = ./.;
          fileset = lib.fileset.unions [
            ./Cargo.toml
            ./Cargo.lock
            ./crates/common
            ./crates/gpapi
            ./crates/openconnect
            ./apps/gpclient
            ./apps/gpservice
            ./apps/gpauth
            ./apps/gpgui-helper/src-tauri
          ];
        };

        # Build the top-level crates of the workspace as individual derivations.
        # This allows consumers to only depend on (and build) only what they need.
        # Though it is possible to build the entire workspace as a single derivation,
        # so this is left up to you on how to organize things
        gpclient = craneLib.buildPackage (individualCrateArgs // {
          pname = "gpclient";
          cargoExtraArgs = "-p gpclient";
          src = fileSetForCrate;
        });
        gpauth = craneLib.buildPackage (individualCrateArgs // {
          pname = "gpauth";
          cargoExtraArgs = "-p gpauth";
          src = fileSetForCrate;
        });
      in
      {
        checks = {
          inherit gpclient gpauth;
        };

        packages = {
          inherit gpclient gpauth;
        };

        apps = {
          gpclient = flake-utils.lib.mkApp {
            drv = gpclient;
          };
          gpauth = flake-utils.lib.mkApp {
            drv = gpauth;
          };
        };

        devShells.default = craneLib.devShell {
          # Inherit inputs from checks.
          checks = self.checks.${system};

          packages = [
            pkgs.cargo-watch
            pkgs.rust-analyzer-nightly
            rustPackages
          ];
        };
      });
}

