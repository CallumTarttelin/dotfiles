import QtQuick
import "lib" as Lib

// Background entry point. Applies saved settings and starts IwdService polling.
Item {
  property var pluginApi: null

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
