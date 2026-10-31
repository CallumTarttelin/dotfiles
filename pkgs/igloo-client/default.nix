{
  lib,
  writeShellApplication,
  igloo,
  tokenFile,
  endpoint,
  jumpHost ? null,
}:
writeShellApplication {
  name = "igloo";
  text = ''
    export IGLOO_ENDPOINT="''${IGLOO_ENDPOINT:-${endpoint}}"
    effective_endpoint="$IGLOO_ENDPOINT"
    next_endpoint=false
    for arg in "$@"; do
      if "$next_endpoint"; then
        effective_endpoint="$arg"
        next_endpoint=false
        continue
      fi
      case "$arg" in
        --) break ;;
        --endpoint) next_endpoint=true ;;
        --endpoint=*) effective_endpoint="''${arg#--endpoint=}" ;;
      esac
    done
    # Only supply nixie's credential and SSH hop to its configured endpoint.
    if [[ "$effective_endpoint" == ${lib.escapeShellArg endpoint} ]]; then
      if [[ -z "''${IGLOO_TOKEN:-}" && -r ${lib.escapeShellArg tokenFile} ]]; then
        # shellcheck source=/dev/null
        source ${lib.escapeShellArg tokenFile}
        export IGLOO_TOKEN
      fi
      ${lib.optionalString (jumpHost != null) ''
      export IGLOO_JUMP_HOST="''${IGLOO_JUMP_HOST-${jumpHost}}"
    ''}
    fi
    exec ${igloo}/bin/igloo "$@"
  '';
}
