# save this as shell.nix
{
  pkgs ? import <nixpkgs> { },
}:

pkgs.mkShell {
  packages = [
    pkgs.nodejs
    pkgs.pnpm
  ];
  shellHook = ''
    export NPM_CONFIG_CACHE=$PWD/.npm
    export PNPM_HOME=$PWD/.pnpm
    export PNPM_STORE_DIR=$PWD/.pnpm-store
  '';
}
