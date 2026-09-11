// Pure parsing and state helpers for the widget. Qt-free so node can test them;
// QML owns every process and every visual element.

var ACCOUNTS_JQ = '{active: (.activeuserid // .activeUserId // ""), accounts: ((.accounts // {}) | map_values({host: (.host // ""), email: (.email // ""), name: (.name // ""), orgId: (.orgId // ""), hasSession: ((.sessionToken // "") != "")}))}'
var PREFS_JQ = '.up // {}'
var DEFAULT_PREFS = { overrideDns: true, tunnelDns: false, preferLocalRoutes: false, upstreamDns: "", matchDomains: "" }
var PENDING_TIMEOUT_MS = { connect: 180000, disconnect: 30000, login: 330000, logout: 30000 }
var HOST_PATTERN = /^(https?:\/\/)?[A-Za-z0-9.-]+(:[0-9]+)?$/

function emptyStatus() {
  return { running: false, connected: false, registered: false, orgId: "", error: "", tunnelIp: "", peers: [] }
}

function parseStatus(stdout) {
  var start = String(stdout || "").indexOf("{")
  if (start < 0) return emptyStatus()

  try {
    var data = JSON.parse(String(stdout).slice(start))
    var peerMap = data.peers && typeof data.peers === "object" ? data.peers : {}
    var peers = Object.keys(peerMap).map(function(key) {
      var peer = peerMap[key] || {}
      return {
        name: String(peer.name || "site " + peer.siteId),
        connected: !!peer.connected,
        rttMs: Math.round((peer.rtt || 0) / 1e6),
        mode: peer.isLocal ? "local" : peer.isRelay ? "relay" : "direct"
      }
    }).sort(function(a, b) { return a.name.localeCompare(b.name) })
    var addresses = data.networkSettings && Array.isArray(data.networkSettings.ipv4_addresses)
      ? data.networkSettings.ipv4_addresses
      : []

    return {
      running: true,
      connected: !!data.connected && !!data.registered,
      registered: !!data.registered,
      orgId: String(data.orgId || ""),
      error: data.error ? String(data.error.message || data.error.code || "") : "",
      tunnelIp: addresses.length > 0 ? String(addresses[0]) : "",
      peers: peers
    }
  } catch (error) {
    return emptyStatus()
  }
}

function emptyAuth() {
  return { loggedIn: false, host: "", email: "", name: "", orgId: "", knownHost: "" }
}

function parseAuth(stdout) {
  try {
    var data = JSON.parse(String(stdout || ""))
    var active = String(data.active || "")
    var accounts = data.accounts && typeof data.accounts === "object" ? data.accounts : {}
    var keys = Object.keys(accounts).sort()
    var account = accounts[active]

    if (!account && active !== "") {
      for (var i = 0; i < keys.length; i++) {
        if (keys[i].toLowerCase() === active.toLowerCase()) {
          account = accounts[keys[i]]
          break
        }
      }
    }

    var loggedIn = !!(account && account.hasSession)
    var knownAccount = account || (keys.length > 0 ? accounts[keys[0]] : null)
    return {
      loggedIn: loggedIn,
      host: loggedIn ? String(account.host || "") : "",
      email: loggedIn ? String(account.email || "") : "",
      name: loggedIn ? String(account.name || "") : "",
      orgId: loggedIn ? String(account.orgId || "") : "",
      knownHost: knownAccount ? String(knownAccount.host || "") : ""
    }
  } catch (error) {
    return emptyAuth()
  }
}

function parsePrefs(stdout) {
  try {
    var data = JSON.parse(String(stdout || ""))
    return {
      overrideDns: typeof data.override_dns === "boolean" ? data.override_dns : DEFAULT_PREFS.overrideDns,
      tunnelDns: typeof data.tunnel_dns === "boolean" ? data.tunnel_dns : DEFAULT_PREFS.tunnelDns,
      preferLocalRoutes: typeof data.prefer_local_routes === "boolean" ? data.prefer_local_routes : DEFAULT_PREFS.preferLocalRoutes,
      upstreamDns: Array.isArray(data.upstream_dns) ? data.upstream_dns.join(",") : "",
      matchDomains: Array.isArray(data.match_domains_dns) ? data.match_domains_dns.join(",") : ""
    }
  } catch (error) {
    return {
      overrideDns: DEFAULT_PREFS.overrideDns,
      tunnelDns: DEFAULT_PREFS.tunnelDns,
      preferLocalRoutes: DEFAULT_PREFS.preferLocalRoutes,
      upstreamDns: DEFAULT_PREFS.upstreamDns,
      matchDomains: DEFAULT_PREFS.matchDomains
    }
  }
}

function deriveState(loggedIn, status, pending) {
  if (pending === "connect" && !status.connected) return "connecting"
  if ((pending === "disconnect" || pending === "logout") && status.running) return "disconnecting"
  if (status.connected) return "connected"
  if (status.running && status.error !== "") return "error"
  if (status.running) return "starting"
  if (!loggedIn) return "loggedOut"
  return "disconnected"
}

function pendingSatisfied(pending, loggedIn, status) {
  if (pending === "connect") return status.connected || status.error !== ""
  if (pending === "disconnect") return !status.running
  if (pending === "login") return loggedIn
  if (pending === "logout") return !loggedIn && !status.running
  return true
}

function stateLabel(state) {
  if (state === "connecting") return "Connecting…"
  if (state === "disconnecting") return "Disconnecting…"
  if (state === "connected") return "Connected"
  if (state === "error") return "Connection error"
  if (state === "starting") return "Starting…"
  if (state === "loggedOut") return "Not logged in"
  return "Disconnected"
}

function safeHost(value) {
  var host = String(value === undefined || value === null ? "" : value).trim()
  return HOST_PATTERN.test(host) ? host : ""
}

function loginArgv(host) {
  var argv = ["omarchy-launch-floating-terminal-with-presentation", "pangolin", "login"]
  var safe = safeHost(host)
  if (safe !== "") argv.push(safe)
  return argv
}

function normalizeList(text) {
  return String(text || "").split(",").map(function(value) { return value.trim() }).filter(function(value) { return value !== "" }).join(",")
}

function sessionExpired(errorText) {
  return /unauthorized/i.test(String(errorText || ""))
}

if (typeof module !== "undefined") {
  module.exports = {
    ACCOUNTS_JQ: ACCOUNTS_JQ,
    PREFS_JQ: PREFS_JQ,
    DEFAULT_PREFS: DEFAULT_PREFS,
    PENDING_TIMEOUT_MS: PENDING_TIMEOUT_MS,
    HOST_PATTERN: HOST_PATTERN,
    parseStatus: parseStatus,
    parseAuth: parseAuth,
    parsePrefs: parsePrefs,
    deriveState: deriveState,
    pendingSatisfied: pendingSatisfied,
    stateLabel: stateLabel,
    safeHost: safeHost,
    loginArgv: loginArgv,
    normalizeList: normalizeList,
    sessionExpired: sessionExpired
  }
}
