import QtQuick
import Quickshell
import qs.Widgets
import "lib" as Lib

NIconButtonHot {
  property ShellScreen screen
  property var pluginApi: null

  icon: Lib.IwdService.signalIcon
  tooltipText: Lib.IwdService.connected
    ? pluginApi?.tr("cc.tooltip.connected", { "ssid": Lib.IwdService.ssid })
    : pluginApi?.tr("cc.tooltip.disconnected")

  hot: Lib.IwdService.connected

  onClicked: {
    if (pluginApi) {
      pluginApi.togglePanel(screen, this);
    }
  }
}
