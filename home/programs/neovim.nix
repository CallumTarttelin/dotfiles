{
  inputs,
  ...
}: {
  home.packages = [
    inputs.nvim.packages.x86_64-linux.default
  ];
}
