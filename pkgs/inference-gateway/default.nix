{
  lib,
  rustPlatform,
  pkg-config,
  zstd,
}:
rustPlatform.buildRustPackage {
  pname = "inference-gateway";
  version = "0.2.0";
  src = lib.cleanSource ./.;
  cargoLock.lockFile = ./Cargo.lock;
  nativeBuildInputs = [pkg-config];
  buildInputs = [zstd];
  doCheck = true;
  meta = {
    description = "Streaming inference journal and Zstd Parquet archive";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "inference-gateway";
  };
}
