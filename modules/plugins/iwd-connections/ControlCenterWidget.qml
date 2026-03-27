import QtQuick
import Quickshell
import qs.Widgets
import "lib" as Lib

NIconButtonHot {
  property ShellScreen screen
  property var pluginApi: null

  icon: Lib.IwdService.signalIcon
  tooltipText: Lib.IwdService.connected
    ? "Wi-Fi: " + Lib.IwdService.ssid
    : "Wi-Fi: Disconnected"

  hot: Lib.IwdService.connected

  onClicked: {
    if (pluginApi) {
      pluginApi.togglePanel(screen, this);
    }
  }
}
