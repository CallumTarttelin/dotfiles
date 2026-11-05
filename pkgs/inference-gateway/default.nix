{
  lib,
  rustPlatform,
}:
rustPlatform.buildRustPackage {
  pname = "inference-gateway";
  version = "0.2.0";
  src = lib.cleanSource ./.;
  cargoLock.lockFile = ./Cargo.lock;
  doCheck = true;
  meta = {
    description = "Streaming inference journal and Zstd Parquet archive";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "inference-gateway";
  };
}
