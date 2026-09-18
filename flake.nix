{
  description = "Rapidsnark Environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  # The MinGW the windows-x86_64 archives are built with. Archives built with one
  # mingw-w64 do not link with another, and consumers link with logos-nix's
  # toolchain, so the archives are built with the same one; relock together.
  inputs.logos-nix.url = "github:logos-co/logos-nix";

  outputs =
    { nixpkgs, logos-nix, ... }:
    let
      lib = nixpkgs.lib;

      rapidsnarkVersion = builtins.head
        (lib.splitString "\n" (builtins.readFile ./RAPIDSNARK_VERSION));

      hashes = (builtins.fromJSON (builtins.readFile ./nix-hashes.json)).rapidsnark.${rapidsnarkVersion};

      forkBase  = "https://github.com/logos-blockchain/logos-blockchain-rust-rapidsnark/releases/download/rapidsnark-pic-v${rapidsnarkVersion}";
      iden3Base = "https://github.com/iden3/rapidsnark/releases/download/v${rapidsnarkVersion}";

      # Linux PIC archives are built by us (see .github/workflows/build-pic-archives.yml);
      # macOS archives are taken from the upstream iden3 release.
      assetUrl = system: {
        "x86_64-linux"   = "${forkBase}/rapidsnark-linux-x86_64-pic-v${rapidsnarkVersion}.zip";
        "aarch64-linux"  = "${forkBase}/rapidsnark-linux-aarch64-pic-v${rapidsnarkVersion}.zip";
        "aarch64-darwin" = "${iden3Base}/rapidsnark-macOS-arm64-v${rapidsnarkVersion}.zip";
        "x86_64-darwin"  = "${iden3Base}/rapidsnark-macOS-x86_64-v${rapidsnarkVersion}.zip";
      }.${system};

      systems = builtins.attrNames hashes;
      forAll  = lib.genAttrs systems;

      mkRapidsnark = system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        pkgs.stdenv.mkDerivation {
          pname   = "rapidsnark";
          version = rapidsnarkVersion;
          phases  = [ "installPhase" ];

          # fetchzip extracts and strips the top-level directory; src points directly to the content.
          src = pkgs.fetchzip {
            url  = assetUrl system;
            hash = hashes.${system};
          };

          # Exposed archives are static. Linux ones are built with -fPIC (see build-pic-archives.yml); remaining are upstream iden3.
          installPhase = ''
            mkdir -p $out
            cp $src/lib/* $out/
          '';

          meta.platforms = builtins.attrNames hashes;

          passthru.version = rapidsnarkVersion;
        };
    in
    {
      # `nix develop .#windows-cross` puts the pinned MinGW on PATH for
      # scripts/build-windows-archives.sh. CI runs the same command.
      devShells.x86_64-linux.windows-cross =
        let
          pkgs = logos-nix.inputs.nixpkgs.legacyPackages.x86_64-linux;
          mingw = pkgs.pkgsCross.mingwW64;
          gmp = mingw.gmp.override { withStatic = true; };
        in
        pkgs.mkShell {
          packages = [ mingw.stdenv.cc pkgs.cmake pkgs.gnumake pkgs.git pkgs.zip ];
          CROSS_GMP_LIB = "${gmp}/lib";
          CROSS_GMP_INCLUDE = "${gmp.dev}/include";
          CROSS_EXTRA_INCLUDES = "-I${mingw.windows.mcfgthreads.dev}/include -I${mingw.windows.pthreads}/include";
          TOOLCHAIN_ID = "x86_64-w64-mingw32-gcc ${mingw.stdenv.cc.cc.version}; logos-nix ${logos-nix.rev or "dirty"}";
        };

      packages = forAll (system: {
        rapidsnark = mkRapidsnark system;
        default    = mkRapidsnark system;
      });
    };
}
