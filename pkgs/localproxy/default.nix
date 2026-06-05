{pkgs}:
pkgs.buildGoModule {
  pname = "localproxy";
  version = "0.1.0";

  src = ./.;
  vendorHash = null;
  subPackages = ["."];

  env.CGO_ENABLED = 0;

  ldflags = [
    "-s"
    "-w"
    "-X main.defaultHaproxy=${pkgs.haproxy}/bin/haproxy"
  ];
}
