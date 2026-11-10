{
  lib,
  rustPlatform,
  pkg-config,
  sqlite,
}:
rustPlatform.buildRustPackage {
  pname = "remote-oidc-token";
  version = "0.2.0";
  src = lib.cleanSource ./.;
  cargoLock.lockFile = ./Cargo.lock;
  # Link nixpkgs' SQLite instead of the copy rusqlite bundles for plain cargo builds.
  env.LIBSQLITE3_SYS_USE_PKG_CONFIG = "1";
  nativeBuildInputs = [pkg-config];
  buildInputs = [sqlite];
  doCheck = true;
  meta = {
    description = "Copy an OIDC web app's access token from the work browser to a remote machine";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "remote-oidc-token";
  };
}
