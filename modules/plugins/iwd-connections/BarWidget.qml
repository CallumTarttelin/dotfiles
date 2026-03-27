import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Modules.Bar.Extras
import qs.Services.UI
import "lib" as Lib

Item {
  id: root

  property ShellScreen screen
  property var pluginApi: null
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0
  property var widgetMetadata: ({})
  property var widgetSettings: ({})

  readonly property string screenName: screen ? screen.name : ""
  readonly property string barPosition: Settings.getBarPositionForScreen(screenName)
  readonly property bool isBarVertical: barPosition === "left" || barPosition === "right"

  implicitWidth: pill.width
  implicitHeight: pill.height

  BarPill {
    id: pill
    screen: root.screen
    oppositeDirection: BarService.getPillDirection(root)
    icon: Lib.IwdService.signalIcon
    text: Lib.IwdService.connected ? Lib.IwdService.ssid : "Disconnected"
    tooltipText: {
      if (!Lib.IwdService.connected)
        return "Wi-Fi disconnected";
      return Lib.IwdService.ssid + " (" + Lib.IwdService.signalDbm + " dBm)"
           + (Lib.IwdService.ipv4 ? "\n" + Lib.IwdService.ipv4 : "");
    }

    onClicked: {
      if (root.pluginApi) {
        root.pluginApi.togglePanel(root.screen, root);
      }
    }
  }
}
