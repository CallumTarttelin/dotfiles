let
  nixshark = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHxgENtK22oTNndrl3ODUJvxFO9EVJ+M2qv7Zfel04Dw ssh@callumtarttelin.com";
  nixie = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINNbVyvd7na036VTmMkgG94N/Mc2KJkAfZgNQODa5zhX ssh@callumtarttelin.com";
  nixwork = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPWkL2XmmtBm9p7DttGzVsbH8TuaVqzeGjVt5fz7MtX/ ssh@callumtarttelin.com";
  allKeys = [nixshark nixie nixwork];
in {
  "tarttelin.age".publicKeys = allKeys;
  "root.age".publicKeys = allKeys;
  "borgrepo.age".publicKeys = allKeys;
  "borgpass.age".publicKeys = allKeys;
  "forgejo-runner.age".publicKeys = allKeys;
  "forgejo-runner-native.age".publicKeys = allKeys;
  "yubi.age".publicKeys = allKeys;
  "cloudflare.age".publicKeys = allKeys;
  "k8s-minio.age".publicKeys = allKeys;
  "k8s-grafana.age".publicKeys = allKeys;
}
