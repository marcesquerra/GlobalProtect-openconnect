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
        # supralist = with pkgs; pkg_libs [openssl webkitgtk libsoup];#"${pkgs.openssl.dev}/lib/pkgconfig";

        # Common arguments can be set here to avoid repeating them later
        commonArgs = {
          inherit src;
          # strictDeps = true;

          buildInputs = [
            # pkgs.libiconv
            pkgs.pkg-config

            pkgs.openssl
            # pkgs.openssl.dev
            # pkgs.brotli.lib
            # pkgs.curl.out
            # pkgs.duktape.out
            # pkgs.e2fsprogs.out
            # pkgs.glibc.out
            # pkgs.glib.out
            # pkgs.gmp.out
            # pkgs.gnutls.out
            # pkgs.icu74.out
            # pkgs.keyutils.lib
            # pkgs.libffi.out
            # pkgs.libgcc.lib
            # pkgs.libidn2.out
            # pkgs.libkrb5.out
            # pkgs.libproxy.out
            # pkgs.libpsl.out
            # pkgs.libssh2.out
            # pkgs.libtasn1.out
            # pkgs.libtool.lib
            # pkgs.libunistring.out
            # pkgs.libuuid.lib
            # pkgs.libxml2.out
            # pkgs.libxslt.out
            # pkgs.lz4.out
            # pkgs.nettle.out
            # pkgs.nghttp2.lib
            # pkgs.nghttp3.out
            # pkgs.openconnect.out
            # pkgs.openssl.out
            # pkgs.p11-kit.out
            # pkgs.pcre2.out
            # pkgs.pcsclite.lib
            # pkgs.stoken.out
            # pkgs.tpm2-tss.out
            # pkgs.xmlsec.out
            # pkgs.xz.out
            # pkgs.zlib.out
            # pkgs.zstd.out
            pkgs.libsoup
            pkgs.webkitgtk
            pkgs.gcc
            pkgs.openconnect
          ];

          # Additional environment variables can be set directly
          # MY_CUSTOM_VAR = "some value";
          PKG_CONFIG_PATH = with pkgs; pkg_libs [libsoup openssl webkitgtk openconnect];#"${pkgs.openssl.dev}/lib/pkgconfig";
          OPENSSL_NO_VENDOR = 1;
          PKG_CONFIG_PATH_FOR_TARGET = "";
        };

        rustPackages = fenix.packages.${system}.complete.withComponents [
            "cargo"
            "llvm-tools"
            "rustc"
          ];

        # craneLibLLvmTools = craneLib.overrideToolchain rustPackages;

        # Build *just* the cargo dependencies (of the entire workspace),
        # so we can reuse all of that work (e.g. via cachix) when running in CI
        # It is *highly* recommended to use something like cargo-hakari to avoid
        # cache misses when building individual top-level-crates
        cargoArtifacts = craneLib.buildDepsOnly (commonArgs // {pname = "cargoArtifacts";});

        individualCrateArgs = commonArgs // {
          inherit cargoArtifacts;
          # inherit (craneLib.crateNameFromCargoToml { inherit src; }) version;
          # inherit version;
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
          # Build the crates as part of `nix flake check` for convenience
          inherit gpclient gpauth;

        #   # Run clippy (and deny all warnings) on the workspace source,
        #   # again, reusing the dependency artifacts from above.
        #   #
        #   # Note that this is done as a separate derivation so that
        #   # we can block the CI if there are issues here, but not
        #   # prevent downstream consumers from building our crate by itself.
        #   my-workspace-clippy = craneLib.cargoClippy (commonArgs // {
        #     inherit cargoArtifacts;
        #     pname = "my-workspace-clippy";
        #     cargoClippyExtraArgs = "--all-targets -- --deny warnings";
        #   });

        #   my-workspace-doc = craneLib.cargoDoc (commonArgs // {
        #     inherit cargoArtifacts;
        #     pname = "my-workspace-doc";
        #   });

        #   # Check formatting
        #   my-workspace-fmt = craneLib.cargoFmt {
        #     inherit src;
        #     pname = "my-workspace-fmt";
        #   };

        #   # Audit dependencies
        #   my-workspace-audit = craneLib.cargoAudit {
        #     inherit src advisory-db;
        #     pname = "my-workspace-audit";
        #   };

        #   # Audit licenses
        #   my-workspace-deny = craneLib.cargoDeny {
        #     inherit src;
        #     pname = "my-workspace-deny";
        #   };

        #   # Run tests with cargo-nextest
        #   # Consider setting `doCheck = false` on other crate derivations
        #   # if you do not want the tests to run twice
        #   my-workspace-nextest = craneLib.cargoNextest (commonArgs // {
        #     inherit cargoArtifacts;
        #     partitions = 1;
        #     partitionType = "count";
        #     pname = "my-workspace-nextest";
        #   });

        #   # Ensure that cargo-hakari is up to date
        #   my-workspace-hakari = craneLib.mkCargoDerivation {
        #     inherit src;
        #     pname = "my-workspace-hakari";
        #     cargoArtifacts = null;
        #     doInstallCargoArtifacts = false;

        #     buildPhaseCargoCommand = ''
        #       cargo hakari generate --diff  # workspace-hack Cargo.toml is up-to-date
        #       cargo hakari manage-deps --dry-run  # all workspace crates depend on workspace-hack
        #       cargo hakari verify
        #     '';

        #     nativeBuildInputs = [
        #       pkgs.cargo-hakari
        #     ];
        #   };
        };

        packages = {
          inherit gpclient gpauth;
          # my-workspace-llvm-coverage = craneLibLLvmTools.cargoLlvmCov (commonArgs // {
          #   inherit cargoArtifacts;
          #   pname = "my-workspace-llvm-coverage";
          # });
        };

        apps = {
          gpclient = flake-utils.lib.mkApp {
            drv = gpclient;
          };
          gpauth = flake-utils.lib.mkApp {
            drv = gpauth;
          };
        #   my-server = flake-utils.lib.mkApp {
        #     drv = my-server;
        #   };
        };

        devShells.default = craneLib.devShell {
          # Inherit inputs from checks.
          checks = self.checks.${system};

          # Additional dev-shell environment variables can be set directly
          # MY_CUSTOM_DEVELOPMENT_VAR = "something else";

          # Extra inputs can be added here; cargo and rustc are provided by default.
          packages = [
            # pkgs.cargo-hakari
            pkgs.cargo-watch
            pkgs.rust-analyzer-nightly
            rustPackages
          ];
        };
      });
}

