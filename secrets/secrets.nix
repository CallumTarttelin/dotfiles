let
  # User keys (for re-keying secrets from workstation)
  nixshark-user = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHxgENtK22oTNndrl3ODUJvxFO9EVJ+M2qv7Zfel04Dw ssh@callumtarttelin.com";
  nixie-user = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINNbVyvd7na036VTmMkgG94N/Mc2KJkAfZgNQODa5zhX ssh@callumtarttelin.com";
  nixwork-user = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPWkL2XmmtBm9p7DttGzVsbH8TuaVqzeGjVt5fz7MtX/ ssh@callumtarttelin.com";

  # Host keys (for agenix decryption at boot)
  nixshark-host = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKntjin/g45e5lK8LAUh+ArjnaT8uw+qw+XMPKElh9c6 root@nixshark";
  nixie-host = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIE+IF0D7WJNCdXYrwFchwu+KxzgHhXZJcNVDqdglZ47 root@nixie";
  nixwork-host = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGPKLf6KmW7jCGvzd2NL1dWUW77CIkBaShERbC5QITZ5 root@nixwork";

  allKeys = [nixshark-user nixie-user nixwork-user nixshark-host nixie-host nixwork-host];
in {
  "tarttelin.age".publicKeys = allKeys;
  "root.age".publicKeys = allKeys;
  "borgrepo.age".publicKeys = allKeys;
  "borgpass.age".publicKeys = allKeys;
  "forgejo-runner.age".publicKeys = allKeys;
  "forgejo-runner-native.age".publicKeys = allKeys;
  "vaultwarden.age".publicKeys = allKeys;
  "cloudflare.age".publicKeys = allKeys;
  "k8s-minio.age".publicKeys = allKeys;
  "k8s-grafana.age".publicKeys = allKeys;
  "cache-key.age".publicKeys = allKeys;
}
