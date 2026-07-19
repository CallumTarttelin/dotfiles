{
  google-cloud-sdk,
  lib,
  makeWrapper,
  openssh,
  python3,
  stdenvNoCC,
}:
stdenvNoCC.mkDerivation {
  pname = "gcloud-remote-login";
  version = "0.1.0";

  src = lib.cleanSource ./.;
  nativeBuildInputs = [makeWrapper];

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    ${python3}/bin/python3 -m unittest discover -s tests -v
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin" "$out/libexec/gcloud-remote-login"
    cp gcloud_remote_login.py "$out/libexec/gcloud-remote-login/gcloud_remote_login.py"
    makeWrapper ${python3}/bin/python3 "$out/bin/gcloud-remote-login" \
      --add-flags "$out/libexec/gcloud-remote-login/gcloud_remote_login.py" \
      --prefix PATH : ${lib.makeBinPath [openssh google-cloud-sdk]}
    runHook postInstall
  '';

  meta = {
    description = "Complete a remote gcloud no-browser login using a local browser";
    license = lib.licenses.mit;
    mainProgram = "gcloud-remote-login";
    platforms = lib.platforms.unix;
  };
}
