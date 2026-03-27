import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets
import "lib" as Lib

ColumnLayout {
  id: root

  property var pluginApi: null
  readonly property real preferredWidth: 380

  readonly property var settings: pluginApi?.pluginSettings ?? ({})

  spacing: Style.marginL
  width: parent.width

  function saveSettings() {
    if (!pluginApi) return;
    pluginApi.pluginSettings.iface = ifaceField.text;
    pluginApi.pluginSettings.pollInterval = Math.round(pollSlider.value) * 1000;
    pluginApi.saveSettings();
    Lib.IwdService.iface = ifaceField.text;
    Lib.IwdService.pollInterval = Math.round(pollSlider.value) * 1000;
  }

  // -- Interface name --
  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.marginS

    NText {
      text: "Wireless Interface"
      pointSize: Style.fontSizeM
      color: Color.mOnSurface
    }

    NText {
      text: "The iwd station name (e.g. wlan0, wlan1)"
      pointSize: Style.fontSizeS
      color: Color.mOnSurfaceVariant
    }

    TextField {
      id: ifaceField
      Layout.fillWidth: true
      text: root.settings.iface ?? "wlan0"
      color: Color.mOnSurface
      font.pointSize: Style.fontSizeM
      background: Rectangle {
        color: Color.smartAlpha(Color.mSurface)
        radius: Style.iRadiusS
        border.color: ifaceField.activeFocus ? Color.mPrimary : Color.mOutline
        border.width: 1
      }
    }
  }

  // -- Poll interval --
  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.marginS

    NText {
      text: "Poll Interval"
      pointSize: Style.fontSizeM
      color: Color.mOnSurface
    }

    NText {
      text: "How often to check connection status (seconds)"
      pointSize: Style.fontSizeS
      color: Color.mOnSurfaceVariant
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginM

      Slider {
        id: pollSlider
        Layout.fillWidth: true
        from: 1
        to: 30
        stepSize: 1
        value: (root.settings.pollInterval ?? 5000) / 1000
      }

      NText {
        text: Math.round(pollSlider.value) + "s"
        pointSize: Style.fontSizeM
        color: Color.mOnSurface
        Layout.preferredWidth: 30
      }
    }
  }

  // -- Current status --
  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.marginS

    NText {
      text: "Current Status"
      pointSize: Style.fontSizeM
      color: Color.mOnSurface
    }

    GridLayout {
      Layout.fillWidth: true
      columns: 2
      columnSpacing: Style.marginL
      rowSpacing: Style.marginXS

      NText { text: "Interface:"; pointSize: Style.fontSizeS; color: Color.mOnSurfaceVariant }
      NText { text: Lib.IwdService.iface; pointSize: Style.fontSizeS; color: Color.mOnSurface }

      NText { text: "State:"; pointSize: Style.fontSizeS; color: Color.mOnSurfaceVariant }
      NText { text: Lib.IwdService.state; pointSize: Style.fontSizeS; color: Color.mOnSurface }

      NText { text: "SSID:"; pointSize: Style.fontSizeS; color: Color.mOnSurfaceVariant }
      NText { text: Lib.IwdService.ssid || "\u2014"; pointSize: Style.fontSizeS; color: Color.mOnSurface }

      NText { text: "Signal:"; pointSize: Style.fontSizeS; color: Color.mOnSurfaceVariant }
      NText { text: Lib.IwdService.connected ? Lib.IwdService.signalDbm + " dBm" : "\u2014"; pointSize: Style.fontSizeS; color: Color.mOnSurface }

      NText { text: "IPv4:"; pointSize: Style.fontSizeS; color: Color.mOnSurfaceVariant }
      NText { text: Lib.IwdService.ipv4 || "\u2014"; pointSize: Style.fontSizeS; color: Color.mOnSurface }

      NText { text: "Security:"; pointSize: Style.fontSizeS; color: Color.mOnSurfaceVariant }
      NText { text: Lib.IwdService.security || "\u2014"; pointSize: Style.fontSizeS; color: Color.mOnSurface }
    }
  }
}
