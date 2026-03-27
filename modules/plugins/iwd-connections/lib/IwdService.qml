pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Polls iwd for wifi state and provides connect/disconnect/scan actions.
Singleton {
  id: root

  readonly property string tag: "iwd-connections"

  property string iface: "wlan0"
  property int pollInterval: 5000

  // Connection state
  property bool connected: false
  property string ssid: ""
  property int signalDbm: -100
  property string security: ""
  property string state: "disconnected" // disconnected, connecting, connected
  property string ipv4: ""

  // Available networks
  property var networks: [] // [{name, security, signal, connected}]

  // Known (saved) networks
  property var knownNetworks: [] // [{name, security, lastConnected}]

  // Busy flags
  property bool scanning: false
  property bool actionInProgress: false

  // Error state
  property string lastError: ""

  // Signal strength as 0-4 bars
  readonly property int signalBars: {
    if (signalDbm >= -50) return 4;
    if (signalDbm >= -60) return 3;
    if (signalDbm >= -70) return 2;
    if (signalDbm >= -80) return 1;
    return 0;
  }

  readonly property string signalIcon: {
    if (!connected) return "wifi-off";
    if (signalBars >= 3) return "wifi";
    if (signalBars >= 2) return "wifi-2";
    if (signalBars >= 1) return "wifi-1";
    return "wifi-0";
  }

  function stripAnsi(text) {
    return text.replace(/\x1b\[[0-9;]*m/g, "");
  }

  // --- Status polling ---

  Timer {
    id: statusTimer
    interval: root.pollInterval
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      Logger.d(root.tag, "polling status for", root.iface);
      statusProc.running = true;
    }
  }

  Process {
    id: statusProc
    command: ["iwctl", "station", root.iface, "show"]
    stdout: StdioCollector {
      onStreamFinished: root.parseStatus(this.text)
    }
    stderr: StdioCollector {
      onStreamFinished: {
        var msg = root.stripAnsi(this.text).trim();
        if (msg) root.handleIfaceError(msg);
      }
    }
    onExited: (code, status) => {
      Logger.d(root.tag, "status process exited, code:", code);
    }
  }

  function handleIfaceError(msg) {
    Logger.w(root.tag, "interface error:", msg);
    if (msg.indexOf("No station") >= 0 || msg.indexOf("not found") >= 0) {
      root.state = "unavailable";
      root.connected = false;
      root.ssid = "";
      root.signalDbm = -100;
      root.lastError = "Interface '" + root.iface + "' not found";
    }
  }

  function parseStatus(output) {
    var clean = stripAnsi(output);
    var lines = clean.split("\n");
    var props = {};
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      var match = line.match(/^\s+(\S[\w\s]*\S)\s{2,}(\S.*)\s*$/);
      if (match) {
        props[match[1].trim()] = match[2].trim();
      }
    }

    Logger.d(root.tag, "parsed status props:", JSON.stringify(props));

    root.lastError = "";
    root.state = (props["State"] || "disconnected").toLowerCase();
    root.connected = root.state === "connected";
    root.ssid = props["Connected network"] || "";
    root.security = props["Security"] || "";
    root.ipv4 = props["IPv4 address"] || "";

    var rssiStr = props["RSSI"] || props["AverageRSSI"] || "";
    var rssiMatch = rssiStr.match(/-?\d+/);
    root.signalDbm = rssiMatch ? parseInt(rssiMatch[0]) : -100;

    Logger.d(root.tag, "state:", root.state, "ssid:", root.ssid,
             "signal:", root.signalDbm, "dBm, bars:", root.signalBars);
  }

  // --- Network scanning ---

  function scan() {
    Logger.d(root.tag, "triggering scan on", root.iface);
    root.scanning = true;
    scanProc.running = true;
  }

  Process {
    id: scanProc
    command: ["iwctl", "station", root.iface, "scan"]
    // iwctl scan produces no stdout — detect completion via running property
    onRunningChanged: {
      if (!running) {
        Logger.d(root.tag, "scan trigger complete, waiting 2s for results");
        scanFetchDelay.start();
      }
    }
    onExited: (code, status) => {
      Logger.d(root.tag, "scan process exited, code:", code);
    }
    stderr: StdioCollector {
      onStreamFinished: {
        var msg = root.stripAnsi(this.text).trim();
        if (msg) {
          Logger.w(root.tag, "scan stderr:", msg);
          root.lastError = msg;
          root.scanning = false;
        }
      }
    }
  }

  Timer {
    id: scanFetchDelay
    interval: 2000
    repeat: false
    onTriggered: {
      Logger.d(root.tag, "fetching network list after scan");
      networkListProc.running = true;
    }
  }

  function fetchNetworks() {
    Logger.d(root.tag, "fetching network list");
    networkListProc.running = true;
  }

  Process {
    id: networkListProc
    command: ["iwctl", "station", root.iface, "get-networks"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.parseNetworks(this.text);
        root.scanning = false;
      }
    }
    onExited: (code, status) => {
      Logger.d(root.tag, "get-networks exited, code:", code);
    }
  }

  function parseNetworks(output) {
    var clean = stripAnsi(output);
    var lines = clean.split("\n");
    var result = [];
    var separatorCount = 0;

    Logger.d(root.tag, "parsing networks, lines:", lines.length);

    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      // Separator lines (may have leading/trailing whitespace)
      if (line.match(/^\s*-{10,}\s*$/)) {
        separatorCount++;
        continue;
      }
      // Need two separators before body (title + column headers)
      if (separatorCount < 2) continue;
      if (line.trim() === "") continue;

      // Lines look like:
      // "  >   Hyperoptic Fibre 9613             psk                 ****"
      // "      SKYRRSTG                          psk                 **"
      var isConnected = line.substring(0, 6).indexOf(">") >= 0;

      var trimmed = line.substring(6).replace(/\s+$/, "");
      var starMatch = trimmed.match(/(\*+)\s*$/);
      var signalStars = starMatch ? starMatch[1].length : 0;

      var withoutSignal = trimmed.replace(/\*+\s*$/, "").replace(/\s+$/, "");
      var secMatch = withoutSignal.match(/\s+(psk|open|8021x|wep|owe|wpa\S*)\s*$/i);
      var sec = secMatch ? secMatch[1] : "unknown";
      var name = withoutSignal.replace(/\s+(psk|open|8021x|wep|owe|wpa\S*)\s*$/i, "").trim();

      if (name) {
        Logger.d(root.tag, "found network:", name, "security:", sec,
                 "signal:", signalStars, "connected:", isConnected);
        result.push({
          name: name,
          security: sec,
          signal: signalStars,
          connected: isConnected
        });
      }
    }

    // Sort: connected first, then by signal strength descending
    result.sort(function(a, b) {
      if (a.connected !== b.connected) return a.connected ? -1 : 1;
      return b.signal - a.signal;
    });

    Logger.d(root.tag, "parsed", result.length, "networks (separators found:", separatorCount + ")");
    root.networks = result;
  }

  // --- Known networks ---

  function fetchKnownNetworks() {
    Logger.d(root.tag, "fetching known networks");
    knownNetworksProc.running = true;
  }

  Process {
    id: knownNetworksProc
    command: ["iwctl", "known-networks", "list"]
    stdout: StdioCollector {
      onStreamFinished: root.parseKnownNetworks(this.text)
    }
    onExited: (code, status) => {
      Logger.d(root.tag, "known-networks exited, code:", code);
    }
  }

  function parseKnownNetworks(output) {
    var clean = stripAnsi(output);
    var lines = clean.split("\n");
    var result = [];
    var separatorCount = 0;

    Logger.d(root.tag, "parsing known networks, lines:", lines.length);

    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      if (line.match(/^\s*-{10,}\s*$/)) {
        separatorCount++;
        continue;
      }
      if (separatorCount < 2) continue;
      if (line.trim() === "") continue;

      var trimmed = line.trim();
      var secMatch = trimmed.match(/^(.+?)\s{2,}(psk|open|8021x|wep|owe)\s{2,}(.+)$/i);
      if (secMatch) {
        Logger.d(root.tag, "found known network:", secMatch[1].trim());
        result.push({
          name: secMatch[1].trim(),
          security: secMatch[2],
          lastConnected: secMatch[3].trim()
        });
      }
    }

    Logger.d(root.tag, "parsed", result.length, "known networks");
    root.knownNetworks = result;
  }

  function forgetNetwork(networkName) {
    Logger.i(root.tag, "forgetting network:", networkName);
    forgetProc.command = ["iwctl", "known-networks", networkName, "forget"];
    forgetProc.running = true;
  }

  Process {
    id: forgetProc
    onRunningChanged: {
      if (!running) root.fetchKnownNetworks();
    }
    onExited: (code, status) => {
      Logger.d(root.tag, "forget exited, code:", code);
    }
  }

  // --- Actions ---

  function connect(networkName) {
    Logger.i(root.tag, "connecting to:", networkName);
    root.lastError = "";
    root.actionInProgress = true;
    connectProc.command = ["iwctl", "station", root.iface, "connect", networkName];
    connectProc.running = true;
  }

  function connectWithPassphrase(networkName, passphrase) {
    Logger.i(root.tag, "connecting to:", networkName, "(with passphrase)");
    root.lastError = "";
    root.actionInProgress = true;
    connectPskProc.command = ["iwctl", "--passphrase", passphrase,
                              "station", root.iface, "connect", networkName];
    connectPskProc.running = true;
  }

  function disconnect() {
    Logger.i(root.tag, "disconnecting from:", root.ssid);
    root.lastError = "";
    root.actionInProgress = true;
    disconnectProc.running = true;
  }

  Process {
    id: connectProc
    onRunningChanged: {
      if (!running) {
        root.actionInProgress = false;
        statusProc.running = true;
      }
    }
    onExited: (code, status) => {
      Logger.d(root.tag, "connect exited, code:", code);
      if (code !== 0) Logger.w(root.tag, "connect failed with code:", code);
    }
    stderr: StdioCollector {
      onStreamFinished: {
        var msg = root.stripAnsi(this.text).trim();
        if (msg) {
          Logger.w(root.tag, "connect stderr:", msg);
          root.lastError = msg;
        }
      }
    }
  }

  Process {
    id: connectPskProc
    onRunningChanged: {
      if (!running) {
        root.actionInProgress = false;
        statusProc.running = true;
      }
    }
    onExited: (code, status) => {
      Logger.d(root.tag, "connect (psk) exited, code:", code);
      if (code !== 0) Logger.w(root.tag, "connect (psk) failed with code:", code);
    }
    stderr: StdioCollector {
      onStreamFinished: {
        var msg = root.stripAnsi(this.text).trim();
        if (msg) {
          Logger.w(root.tag, "connect (psk) stderr:", msg);
          root.lastError = msg;
        }
      }
    }
  }

  Process {
    id: disconnectProc
    command: ["iwctl", "station", root.iface, "disconnect"]
    onRunningChanged: {
      if (!running) {
        root.actionInProgress = false;
        statusProc.running = true;
      }
    }
    onExited: (code, status) => {
      Logger.d(root.tag, "disconnect exited, code:", code);
    }
    stderr: StdioCollector {
      onStreamFinished: {
        var msg = root.stripAnsi(this.text).trim();
        if (msg) {
          Logger.w(root.tag, "disconnect stderr:", msg);
          root.lastError = msg;
        }
      }
    }
  }
}
