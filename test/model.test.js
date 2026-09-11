const test = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../Model.js")

const liveStatus = JSON.stringify({
  connected: true,
  registered: true,
  orgId: "org-1",
  peers: {
    second: { siteId: "site-2", name: "server-newt", connected: true, rtt: 46000000, isRelay: true, isLocal: false },
    first: { siteId: "site-1", name: "nanoclaw-newt", connected: true, rtt: 1600000, isRelay: false, isLocal: true }
  },
  networkSettings: { ipv4_addresses: ["100.90.128.9"] }
})

const stoppedStatus = Model.parseStatus("No client is currently running")

test("parseStatus maps live client JSON", () => {
  assert.deepEqual(Model.parseStatus(liveStatus), {
    running: true,
    connected: true,
    registered: true,
    orgId: "org-1",
    error: "",
    tunnelIp: "100.90.128.9",
    peers: [
      { name: "nanoclaw-newt", connected: true, rttMs: 2, mode: "local" },
      { name: "server-newt", connected: true, rttMs: 46, mode: "relay" }
    ]
  })
})

test("parseStatus treats non-JSON output as stopped", () => {
  assert.deepEqual(stoppedStatus, {
    running: false,
    connected: false,
    registered: false,
    orgId: "",
    error: "",
    tunnelIp: "",
    peers: []
  })
})

test("parseStatus skips an update notice before JSON", () => {
  assert.equal(Model.parseStatus("A new version is available: 0.17.0\n" + liveStatus).connected, true)
})

test("parseAuth retains the first known host after logout", () => {
  assert.deepEqual(Model.parseAuth(JSON.stringify({
    active: "",
    accounts: {
      user: { host: "https://pangolin.terrifiedbug.com", email: "danny@example.com", name: "Danny", orgId: "org-1", hasSession: false }
    }
  })), {
    loggedIn: false,
    host: "",
    email: "",
    name: "",
    orgId: "",
    knownHost: "https://pangolin.terrifiedbug.com"
  })
})

test("parseAuth maps a logged-in account case-insensitively", () => {
  assert.deepEqual(Model.parseAuth(JSON.stringify({
    active: "USER-ID",
    accounts: {
      "user-id": { host: "pangolin.example.com", email: "danny@example.com", name: "Danny", orgId: "org-1", hasSession: true }
    }
  })), {
    loggedIn: true,
    host: "pangolin.example.com",
    email: "danny@example.com",
    name: "Danny",
    orgId: "org-1",
    knownHost: "pangolin.example.com"
  })
})

test("parseAuth returns an empty result for empty output", () => {
  assert.deepEqual(Model.parseAuth(""), {
    loggedIn: false,
    host: "",
    email: "",
    name: "",
    orgId: "",
    knownHost: ""
  })
})

test("parsePrefs supplies CLI defaults for unset values", () => {
  assert.deepEqual(Model.parsePrefs("{}"), Model.DEFAULT_PREFS)
})

test("parsePrefs maps explicit booleans and DNS lists", () => {
  assert.deepEqual(Model.parsePrefs('{"override_dns":false,"upstream_dns":["10.0.0.53","1.1.1.1"]}'), {
    overrideDns: false,
    tunnelDns: false,
    preferLocalRoutes: false,
    upstreamDns: "10.0.0.53,1.1.1.1",
    matchDomains: ""
  })
})

test("deriveState follows transition and status precedence", () => {
  assert.equal(Model.deriveState(true, stoppedStatus, "connect"), "connecting")
  assert.equal(Model.deriveState(true, { running: true, connected: false, error: "" }, "disconnect"), "disconnecting")
  assert.equal(Model.deriveState(true, { running: false, connected: true, error: "" }, "disconnect"), "connected")
  assert.equal(Model.deriveState(true, { running: true, connected: false, error: "unauthorized" }, ""), "error")
  assert.equal(Model.deriveState(true, { running: true, connected: false, error: "" }, ""), "starting")
  assert.equal(Model.deriveState(false, stoppedStatus, ""), "loggedOut")
  assert.equal(Model.deriveState(true, stoppedStatus, ""), "disconnected")
})

test("pendingSatisfied waits for observed transition completion", () => {
  assert.equal(Model.pendingSatisfied("connect", true, { connected: false, error: "" }), false)
  assert.equal(Model.pendingSatisfied("connect", true, { connected: false, error: "failed" }), true)
  assert.equal(Model.pendingSatisfied("disconnect", true, { running: false }), true)
  assert.equal(Model.pendingSatisfied("login", true, stoppedStatus), true)
  assert.equal(Model.pendingSatisfied("logout", false, stoppedStatus), true)
  assert.equal(Model.pendingSatisfied("", false, stoppedStatus), true)
})

test("safeHost rejects shell syntax and loginArgv accepts a valid server", () => {
  assert.equal(Model.safeHost("foo; rm -rf /"), "")
  assert.equal(Model.safeHost(" https://pangolin.terrifiedbug.com "), "https://pangolin.terrifiedbug.com")
  assert.deepEqual(Model.loginArgv("https://pangolin.terrifiedbug.com"), [
    "omarchy-launch-floating-terminal-with-presentation",
    "pangolin",
    "login",
    "https://pangolin.terrifiedbug.com"
  ])
})

test("normalizeList mirrors comma-list storage", () => {
  assert.equal(Model.normalizeList(" 10.0.0.53, ,1.1.1.1 "), "10.0.0.53,1.1.1.1")
})

test("processError clears a failed action after a successful retry", () => {
  let error = Model.processError(1, " first write failed ", "fallback")
  assert.equal(error, "first write failed")
  error = Model.processError(0, "", "fallback")
  assert.equal(error, "")
})

test("sessionExpired recognizes unauthorized errors", () => {
  assert.equal(Model.sessionExpired("Unauthorized request"), true)
  assert.equal(Model.sessionExpired("connection refused"), false)
})
