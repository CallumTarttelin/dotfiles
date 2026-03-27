import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets
import "lib" as Lib

Item {
  id: root

  property var pluginApi: null
  property var geometryPlaceholder: null
  property bool allowAttach: true

  readonly property real contentPreferredWidth: Math.round(400 * Style.uiScaleRatio)
  readonly property real contentPreferredHeight: Math.round(520 * Style.uiScaleRatio)

  // Passphrase input state
  property string connectingNetwork: ""
  property bool showPassphrase: false

  // Tab state: 0 = available, 1 = known
  property int activeTab: 0

  readonly property bool ifaceAvailable: Lib.IwdService.state !== "unavailable"

  Component.onCompleted: {
    Lib.IwdService.scan();
    Lib.IwdService.fetchNetworks();
    Lib.IwdService.fetchKnownNetworks();
  }

  // Dismiss passphrase when panel closes
  Connections {
    target: root.pluginApi
    function onPanelOpenScreenChanged() {
      if (!root.pluginApi.panelOpenScreen) dismissPassphrase();
    }
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Style.marginL
    spacing: Style.marginM

    // -- Header --
    NBox {
      Layout.fillWidth: true
      Layout.preferredHeight: headerCol.implicitHeight + Style.margin2M
      color: Color.smartAlpha(Color.mSurfaceVariant)
      radius: Style.radiusM

      ColumnLayout {
        id: headerCol
        anchors.fill: parent
        anchors.margins: Style.marginM
        spacing: Style.marginM

        RowLayout {
          spacing: Style.marginM

          NIcon {
            icon: "wifi"
            pointSize: Style.fontSizeXL
            color: Color.mPrimary
          }

          NText {
            text: "Wi-Fi (iwd)"
            pointSize: Style.fontSizeL
            color: Color.mOnSurface
            Layout.fillWidth: true
          }

          NIconButton {
            icon: "refresh"
            tooltipText: "Scan for networks"
            enabled: !Lib.IwdService.scanning && root.ifaceAvailable
            onClicked: Lib.IwdService.scan()
          }

          NIconButton {
            icon: "x"
            tooltipText: "Close"
            onClicked: {
              if (root.pluginApi)
                root.pluginApi.closePanel(null);
            }
          }
        }

        // Tab bar
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.marginXS

          Repeater {
            model: ["Available", "Saved"]

            NButton {
              Layout.fillWidth: true
              text: modelData
              backgroundColor: root.activeTab === index
                ? Color.mPrimary : Color.smartAlpha(Color.mSurface)
              textColor: root.activeTab === index
                ? Color.mOnPrimary : Color.mOnSurface
              onClicked: {
                root.activeTab = index;
                if (index === 1) Lib.IwdService.fetchKnownNetworks();
              }
            }
          }
        }
      }
    }

    // -- Status bar --
    NBox {
      Layout.fillWidth: true
      Layout.preferredHeight: statusRow.implicitHeight + Style.margin2M
      color: Lib.IwdService.connected
        ? Color.smartAlpha(Color.mPrimary)
        : Color.smartAlpha(Color.mSurfaceVariant)
      radius: Style.radiusM

      RowLayout {
        id: statusRow
        anchors.fill: parent
        anchors.margins: Style.marginM
        spacing: Style.marginM

        NIcon {
          icon: Lib.IwdService.signalIcon
          pointSize: Style.fontSizeL
          color: Lib.IwdService.connected ? Color.mOnPrimary : Color.mOnSurface
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 2

          NText {
            text: {
              if (Lib.IwdService.state === "unavailable")
                return "Interface unavailable";
              if (Lib.IwdService.actionInProgress)
                return "Connecting...";
              return Lib.IwdService.connected ? Lib.IwdService.ssid : "Not connected";
            }
            pointSize: Style.fontSizeM
            color: Lib.IwdService.connected ? Color.mOnPrimary : Color.mOnSurface
          }

          NText {
            visible: Lib.IwdService.connected
            text: Lib.IwdService.ipv4 + "  " + Lib.IwdService.signalDbm + " dBm"
            pointSize: Style.fontSizeS
            color: Lib.IwdService.connected
              ? Qt.rgba(Color.mOnPrimary.r, Color.mOnPrimary.g, Color.mOnPrimary.b, 0.7)
              : Color.mOnSurfaceVariant
          }
        }

        NButton {
          visible: Lib.IwdService.connected
          text: "Disconnect"
          enabled: !Lib.IwdService.actionInProgress
          onClicked: Lib.IwdService.disconnect()
        }
      }
    }

    // -- Error message --
    NBox {
      visible: Lib.IwdService.lastError !== ""
      Layout.fillWidth: true
      Layout.preferredHeight: errorRow.implicitHeight + Style.margin2M
      color: Color.smartAlpha(Color.mError)
      radius: Style.radiusM

      RowLayout {
        id: errorRow
        anchors.fill: parent
        anchors.margins: Style.marginM
        spacing: Style.marginM

        NIcon {
          icon: "alert-triangle"
          pointSize: Style.fontSizeM
          color: Color.mOnError
        }

        NText {
          text: Lib.IwdService.lastError
          pointSize: Style.fontSizeS
          color: Color.mOnError
          Layout.fillWidth: true
          wrapMode: Text.WordWrap
        }
      }
    }

    // -- Passphrase input --
    NBox {
      id: passphraseBox
      visible: root.showPassphrase
      Layout.fillWidth: true
      Layout.preferredHeight: passphraseCol.implicitHeight + Style.margin2M
      color: Color.smartAlpha(Color.mSurfaceVariant)
      radius: Style.radiusM

      ColumnLayout {
        id: passphraseCol
        anchors.fill: parent
        anchors.margins: Style.marginM
        spacing: Style.marginM

        NText {
          text: "Passphrase for " + root.connectingNetwork
          pointSize: Style.fontSizeM
          color: Color.mOnSurface
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.marginS

          TextField {
            id: passphraseField
            Layout.fillWidth: true
            echoMode: TextInput.Password
            placeholderText: "Enter passphrase"
            color: Color.mOnSurface
            font.pointSize: Style.fontSizeM
            background: Rectangle {
              color: Color.smartAlpha(Color.mSurface)
              radius: Style.iRadiusS
              border.color: passphraseField.activeFocus ? Color.mPrimary : Color.mOutline
              border.width: 1
            }

            Keys.onReturnPressed: connectWithPassphrase()
          }

          NButton {
            text: "Connect"
            enabled: passphraseField.text.length > 0 && !Lib.IwdService.actionInProgress
            onClicked: connectWithPassphrase()
          }

          NIconButton {
            icon: "x"
            onClicked: dismissPassphrase()
          }
        }
      }
    }

    // -- Tab content --

    // Available networks tab
    ColumnLayout {
      visible: root.activeTab === 0
      Layout.fillWidth: true
      Layout.fillHeight: true
      spacing: Style.marginXS

      NText {
        text: Lib.IwdService.scanning ? "Scanning..." : "Available Networks"
        pointSize: Style.fontSizeS
        color: Color.mOnSurfaceVariant
      }

      NScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true

        ColumnLayout {
          width: parent.width
          spacing: Style.marginXS

          Repeater {
            model: Lib.IwdService.networks

            NBox {
              required property var modelData
              required property int index

              Layout.fillWidth: true
              Layout.preferredHeight: netRow.implicitHeight + Style.margin2M
              color: modelData.connected
                ? Color.smartAlpha(Color.mPrimary)
                : netMouse.containsMouse
                  ? Color.smartAlpha(Color.mHover)
                  : Color.smartAlpha(Color.mSurfaceVariant)
              radius: Style.radiusM

              MouseArea {
                id: netMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: modelData.connected ? Qt.ArrowCursor : Qt.PointingHandCursor
                onClicked: {
                  if (!modelData.connected && !Lib.IwdService.actionInProgress)
                    attemptConnect(modelData.name, modelData.security);
                }
              }

              RowLayout {
                id: netRow
                anchors.fill: parent
                anchors.margins: Style.marginM
                spacing: Style.marginM

                NIcon {
                  icon: {
                    if (modelData.signal >= 4) return "wifi";
                    if (modelData.signal >= 3) return "wifi-2";
                    if (modelData.signal >= 2) return "wifi-1";
                    return "wifi-0";
                  }
                  pointSize: Style.fontSizeL
                  color: modelData.connected ? Color.mOnPrimary : Color.mOnSurface
                  Layout.preferredWidth: Style.fontSizeXL
                  Layout.alignment: Qt.AlignVCenter
                }

                NText {
                  text: modelData.name
                  pointSize: Style.fontSizeM
                  color: modelData.connected ? Color.mOnPrimary : Color.mOnSurface
                  Layout.fillWidth: true
                  elide: Text.ElideRight
                }

                NIcon {
                  visible: modelData.security !== "open"
                  icon: "lock"
                  pointSize: Style.fontSizeS
                  color: modelData.connected ? Color.mOnPrimary : Color.mOnSurfaceVariant
                  Layout.preferredWidth: Style.fontSizeM
                  Layout.alignment: Qt.AlignVCenter
                }

                NText {
                  visible: modelData.connected
                  text: "Connected"
                  pointSize: Style.fontSizeS
                  color: Color.mOnPrimary
                }
              }
            }
          }

          // Empty state
          NText {
            visible: Lib.IwdService.networks.length === 0 && !Lib.IwdService.scanning
            text: "No networks found. Try scanning."
            pointSize: Style.fontSizeM
            color: Color.mOnSurfaceVariant
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Style.marginXL
          }
        }
      }
    }

    // Known/saved networks tab
    ColumnLayout {
      visible: root.activeTab === 1
      Layout.fillWidth: true
      Layout.fillHeight: true
      spacing: Style.marginXS

      NText {
        text: "Saved Networks"
        pointSize: Style.fontSizeS
        color: Color.mOnSurfaceVariant
      }

      NScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true

        ColumnLayout {
          width: parent.width
          spacing: Style.marginXS

          Repeater {
            model: Lib.IwdService.knownNetworks

            NBox {
              required property var modelData
              required property int index

              Layout.fillWidth: true
              Layout.preferredHeight: knownRow.implicitHeight + Style.margin2M
              color: knownMouse.containsMouse
                ? Color.smartAlpha(Color.mHover)
                : Color.smartAlpha(Color.mSurfaceVariant)
              radius: Style.radiusM

              MouseArea {
                id: knownMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (!Lib.IwdService.actionInProgress)
                    attemptConnect(modelData.name, modelData.security);
                }
              }

              RowLayout {
                id: knownRow
                anchors.fill: parent
                anchors.margins: Style.marginM
                spacing: Style.marginM

                NIcon {
                  icon: "wifi"
                  pointSize: Style.fontSizeL
                  color: Color.mOnSurface
                  Layout.preferredWidth: Style.fontSizeXL
                  Layout.alignment: Qt.AlignVCenter
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: 2

                  NText {
                    text: modelData.name
                    pointSize: Style.fontSizeM
                    color: Color.mOnSurface
                    elide: Text.ElideRight
                  }

                  NText {
                    text: modelData.lastConnected
                    pointSize: Style.fontSizeXS
                    color: Color.mOnSurfaceVariant
                  }
                }

                NIcon {
                  visible: modelData.security !== "open"
                  icon: "lock"
                  pointSize: Style.fontSizeS
                  color: Color.mOnSurfaceVariant
                  Layout.preferredWidth: Style.fontSizeM
                  Layout.alignment: Qt.AlignVCenter
                }

                NIconButton {
                  icon: "trash-2"
                  tooltipText: "Forget network"
                  onClicked: Lib.IwdService.forgetNetwork(modelData.name)
                }
              }
            }
          }

          // Empty state
          NText {
            visible: Lib.IwdService.knownNetworks.length === 0
            text: "No saved networks."
            pointSize: Style.fontSizeM
            color: Color.mOnSurfaceVariant
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Style.marginXL
          }
        }
      }
    }
  }

  function isKnownNetwork(networkName) {
    var known = Lib.IwdService.knownNetworks;
    for (var i = 0; i < known.length; i++) {
      if (known[i].name === networkName) return true;
    }
    return false;
  }

  function attemptConnect(networkName, security) {
    Lib.IwdService.lastError = "";
    // iwd stores credentials for known networks — no passphrase needed
    if (security === "open" || security === "owe" || isKnownNetwork(networkName)) {
      Lib.IwdService.connect(networkName);
    } else {
      root.connectingNetwork = networkName;
      root.showPassphrase = true;
      passphraseField.text = "";
      passphraseField.forceActiveFocus();
    }
  }

  function connectWithPassphrase() {
    if (passphraseField.text.length === 0) return;
    Lib.IwdService.connectWithPassphrase(root.connectingNetwork, passphraseField.text);
    dismissPassphrase();
  }

  function dismissPassphrase() {
    root.showPassphrase = false;
    root.connectingNetwork = "";
    passphraseField.text = "";
  }
}
