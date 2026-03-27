import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "lib" as Lib

// Background entry point. Applies saved settings and starts IwdService polling.
Item {
  id: root
  property var pluginApi: null

  IpcHandler {
    target: "plugin:iwd-connections"

    function toggle() {
      if (pluginApi) {
        pluginApi.withCurrentScreen(screen => {
          pluginApi.togglePanel(screen);
        });
      }
    }
  }

  Component.onCompleted: {
    if (pluginApi && pluginApi.pluginSettings) {
      var s = pluginApi.pluginSettings;
      if (s.iface) Lib.IwdService.iface = s.iface;
      if (s.pollInterval) Lib.IwdService.pollInterval = s.pollInterval;
    }
    // Touch the service to ensure polling starts
    var _ = Lib.IwdService.state;
  }
}
