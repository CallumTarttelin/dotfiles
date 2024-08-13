{pkgs, ...}: {
  home.packages = with pkgs; [
    kicad
    ngspice
    ghdl
    logisim-evolution
  ];
}
