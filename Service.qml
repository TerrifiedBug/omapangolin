import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model
// qmllint disable signal-handler-parameters

// One service owns Pangolin state and actions so each monitor sees the same
// result without starting another poller. Connect and login move to a terminal:
// creating the interface needs sudo plus a FIDO touch, and login's `huh` forms
// require a TTY. Account data is reduced through jq because accounts.json also
// carries the session token and olm secret; those values never enter QML. The
// headless `pangolin down` stops the tunnel before its TTY error, so its exit
// code is deliberately ignored and polling decides when disconnect is done.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string moduleName: "io.github.terrifiedbug.omapangolin"
  readonly property string configDir: Quickshell.env("HOME") + "/.config/pangolin"
  readonly property var cliEnv: ({ "PANGOLIN_CLI_DISABLE_UPDATE_CHECK": "true" })

  property bool loggedIn: false
  property string accountHost: ""
  property string accountEmail: ""
  property string accountName: ""
  property string accountOrg: ""
  property string knownHost: ""
  property var status: Model.parseStatus("")
  property var prefs: Model.parsePrefs("")
  property string pending: ""
  property string actionError: ""
  property var configQueue: []

  state: Model.deriveState(loggedIn, status, pending)
  readonly property bool busy: pending !== ""

  function refresh() {
    if (!statusProc.running) statusProc.running = true
    if (!authProc.running) authProc.running = true
  }

  function refreshPrefs() {
    if (!prefsProc.running) prefsProc.running = true
  }

  function beginPending(kind) {
    pending = kind
    actionError = ""
    pendingTimer.interval = Model.PENDING_TIMEOUT_MS[kind]
    pendingTimer.restart()
    refresh()
  }

  function settle() {
    if (pending !== "" && Model.pendingSatisfied(pending, loggedIn, status)) {
      pending = ""
      pendingTimer.stop()
    }
    if (pending === "logout" && !status.running && !logoutProc.running) logoutProc.running = true
  }

  function connect() {
    if (busy || status.running) return
    Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", "pangolin", "up"])
    beginPending("connect")
  }

  function disconnect() {
    if (busy || !status.running) return
    beginPending("disconnect")
    downProc.running = true
  }

  function login(hostHint) {
    if (busy || loggedIn) return
    Quickshell.execDetached(Model.loginArgv(knownHost || hostHint || ""))
    beginPending("login")
  }

  function logout() {
    if (busy || !loggedIn) return
    beginPending("logout")
    if (status.running) downProc.running = true
  }

  function openLogs() {
    Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", "pangolin", "logs", "client", "-f", "-n", "50"])
  }

  function setPref(key, value) {
    configQueue = configQueue.concat([[key, value]])
    pumpConfig()
  }

  function pumpConfig() {
    if (configProc.running || configQueue.length === 0) return
    var next = configQueue[0]
    configQueue = configQueue.slice(1)
    configProc.command = ["pangolin", "config", "set", next[0], next[1]]
    configProc.running = true
  }

  Timer {
    id: pollTimer
    interval: root.busy ? 1500 : 10000
    running: true
    repeat: true
    triggeredOnStart: true

    onTriggered: root.refresh()
  }

  Timer {
    id: pendingTimer
    repeat: false

    onTriggered: root.pending = ""
  }

  Process {
    id: statusProc
    command: ["pangolin", "status", "client", "--json"]
    environment: root.cliEnv
    stdinEnabled: false

    stdout: StdioCollector {
      waitForEnd: true

      onStreamFinished: {
        root.status = Model.parseStatus(text)
        root.settle()
      }
    }
  }

  Process {
    id: authProc
    command: ["jq", "-c", Model.ACCOUNTS_JQ, root.configDir + "/accounts.json"]
    stdinEnabled: false

    stdout: StdioCollector {
      waitForEnd: true

      onStreamFinished: {
        var auth = Model.parseAuth(text)
        root.loggedIn = auth.loggedIn
        root.accountHost = auth.host
        root.accountEmail = auth.email
        root.accountName = auth.name
        root.accountOrg = auth.orgId
        root.knownHost = auth.knownHost
        root.settle()
      }
    }
  }

  Process {
    id: prefsProc
    command: ["jq", "-c", Model.PREFS_JQ, root.configDir + "/config.json"]
    stdinEnabled: false

    stdout: StdioCollector {
      waitForEnd: true

      onStreamFinished: root.prefs = Model.parsePrefs(text)
    }
  }

  Process {
    id: downProc
    command: ["pangolin", "down", "client"]
    environment: root.cliEnv
    stdinEnabled: false

    onExited: root.refresh()
  }

  Process {
    id: logoutProc
    command: ["pangolin", "logout"]
    environment: root.cliEnv
    stdinEnabled: false

    stderr: StdioCollector {
      id: logoutErr
      waitForEnd: true
    }

    onExited: function(code) {
      if (code !== 0) root.actionError = logoutErr.text.trim() || "pangolin logout failed"
      root.refresh()
    }
  }

  Process {
    id: configProc
    environment: root.cliEnv
    stdinEnabled: false

    stderr: StdioCollector {
      id: configErr
      waitForEnd: true
    }

    onExited: function(code) {
      if (code !== 0) root.actionError = configErr.text.trim() || "pangolin config set failed"
      root.refreshPrefs()
      root.pumpConfig()
    }
  }

  IpcHandler {
    target: "omapangolin"

    function status(): string {
      return JSON.stringify({
        state: root.state,
        loggedIn: root.loggedIn,
        connected: root.status.connected,
        account: root.accountEmail,
        host: root.accountHost,
        org: root.accountOrg || root.status.orgId,
        peers: root.status.peers.length,
        tunnelIp: root.status.tunnelIp,
        error: root.status.error
      })
    }

    function connect(): string {
      root.connect()
      return "ok"
    }

    function disconnect(): string {
      root.disconnect()
      return "ok"
    }

    function login(): string {
      root.login("")
      return "ok"
    }

    function logout(): string {
      root.logout()
      return "ok"
    }

    function refresh(): string {
      root.refresh()
      root.refreshPrefs()
      return "ok"
    }

    function ping(): string {
      return "ok"
    }
  }

  Component.onCompleted: root.refreshPrefs()
}
