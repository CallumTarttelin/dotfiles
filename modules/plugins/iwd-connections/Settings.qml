import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets
import "lib" as Lib

ColumnLayout {
  id: root

  property var pluginApi: null

  property var cfg: pluginApi?.pluginSettings || ({})
  property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})

  // Edit copies of settings
  property string editIface: cfg.iface ?? defaults.iface ?? "wlan0"
  property int editPollInterval: (cfg.pollInterval ?? defaults.pollInterval ?? 5000) / 1000

  spacing: Style.marginL

  function saveSettings() {
    if (!pluginApi) return;
    pluginApi.pluginSettings.iface = root.editIface;
    pluginApi.pluginSettings.pollInterval = root.editPollInterval * 1000;
    pluginApi.saveSettings();
    Lib.IwdService.iface = root.editIface;
    Lib.IwdService.pollInterval = root.editPollInterval * 1000;
  }

  // -- Interface name --
  NTextInput {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.iface.label")
    description: pluginApi?.tr("settings.iface.desc")
    text: root.editIface
    defaultValue: defaults.iface ?? "wlan0"
    onTextChanged: root.editIface = text
  }

  // -- Poll interval --
  NValueSlider {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.poll.label")
    description: pluginApi?.tr("settings.poll.desc")
    from: 1
    to: 30
    stepSize: 1
    value: root.editPollInterval
    text: Math.round(value) + "s"
    defaultValue: (defaults.pollInterval ?? 5000) / 1000
    onMoved: value => root.editPollInterval = Math.round(value)
  }

  // -- Current status --
  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.marginS

    NText {
      text: pluginApi?.tr("settings.status.title")
      pointSize: Style.fontSizeM
      color: Color.mOnSurface
    }

    GridLayout {
      Layout.fillWidth: true
      columns: 2
      columnSpacing: Style.marginL
      rowSpacing: Style.marginXS

      NText { text: pluginApi?.tr("settings.status.interface"); pointSize: Style.fontSizeS; color: Color.mOnSurfaceVariant }
      NText { text: Lib.IwdService.iface; pointSize: Style.fontSizeS; color: Color.mOnSurface }

      NText { text: pluginApi?.tr("settings.status.state"); pointSize: Style.fontSizeS; color: Color.mOnSurfaceVariant }
      NText { text: Lib.IwdService.state; pointSize: Style.fontSizeS; color: Color.mOnSurface }

      NText { text: pluginApi?.tr("settings.status.ssid"); pointSize: Style.fontSizeS; color: Color.mOnSurfaceVariant }
      NText { text: Lib.IwdService.ssid || pluginApi?.tr("settings.status.none"); pointSize: Style.fontSizeS; color: Color.mOnSurface }

      NText { text: pluginApi?.tr("settings.status.signal"); pointSize: Style.fontSizeS; color: Color.mOnSurfaceVariant }
      NText { text: Lib.IwdService.connected ? Lib.IwdService.signalDbm + " dBm" : pluginApi?.tr("settings.status.none"); pointSize: Style.fontSizeS; color: Color.mOnSurface }

      NText { text: pluginApi?.tr("settings.status.ipv4"); pointSize: Style.fontSizeS; color: Color.mOnSurfaceVariant }
      NText { text: Lib.IwdService.ipv4 || pluginApi?.tr("settings.status.none"); pointSize: Style.fontSizeS; color: Color.mOnSurface }

      NText { text: pluginApi?.tr("settings.status.security"); pointSize: Style.fontSizeS; color: Color.mOnSurfaceVariant }
      NText { text: Lib.IwdService.security || pluginApi?.tr("settings.status.none"); pointSize: Style.fontSizeS; color: Color.mOnSurface }
    }
  }
}
