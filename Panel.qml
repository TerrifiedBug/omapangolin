pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// One button shows the shared service state and opens controls for the tunnel,
// account, peers, logs, and the CLI's DNS and routing preferences. This direct
// panel keeps no mutable copy of Pangolin state, so every monitor stays in sync.
Panel {
  id: root
  moduleName: "io.github.terrifiedbug.omapangolin"
  manageIpc: false

  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function" ? bar.shell.serviceFor(moduleName) : null
  state: service ? service.state : "disconnected"
  readonly property bool busy: service ? service.busy : false
  readonly property var status: service ? service.status : Model.parseStatus("")
  readonly property var prefs: service ? service.prefs : Model.parsePrefs("")
  readonly property string hostHint: String(setting("host", ""))
  readonly property string problem: !service ? "Service not loaded — restart the shell" : (service.actionError || "")
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dimForeground: Qt.darker(contentForeground, 1.6)
  readonly property string accountMeta: service && service.loggedIn ? service.accountEmail : "Log in to connect"
  readonly property string heroDetail: ""

  function quickToggle() {
    if (!service || busy) return
    if (status.running) service.disconnect()
    else if (service.loggedIn) service.connect()
    else root.open()
  }

  function commitList(key, text) {
    if (!service) return
    var value = Model.normalizeList(text)
    var current = key === "up.upstream_dns" ? prefs.upstreamDns : prefs.matchDomains
    if (value === current) return
    service.setPref(key, value)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    if (!opened || !service) return
    service.refresh()
    service.refreshPrefs()
  }

  onPrefsChanged: {
    upstreamField.text = prefs.upstreamDns
    matchField.text = prefs.matchDomains
  }

  Timer {
    interval: 3000
    running: root.opened
    repeat: true

    onTriggered: if (root.service) root.service.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      PangolinIcon {
        anchors.centerIn: parent
        iconSize: Style.space(12)
        busy: root.busy
      }
    }
    active: root.state === "error"
    dimmed: root.state === "disconnected" || root.state === "loggedOut"
    tooltipText: "Pangolin · " + Model.stateLabel(root.state)
      + (root.service && root.service.loggedIn ? " · right-click to connect/disconnect" : "")

    onPressed: function(b) {
      if (b === Qt.RightButton) root.quickToggle()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: upstreamField.activeFocus || matchField.activeFocus

      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(10)

        Item {
          width: parent.width
          implicitHeight: Math.max(sectionHeader.implicitHeight, tunnelLabel.implicitHeight)

          PanelSectionHeader {
            id: sectionHeader
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "PANGOLIN"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
          }

          Text {
            id: tunnelLabel
            textFormat: Text.PlainText
            visible: root.status.connected && root.status.tunnelIp !== ""
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.status.tunnelIp
            color: root.dimForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }

        PanelHero {
          width: parent.width
          title: Model.stateLabel(root.state)
          meta: root.accountMeta
          detail: root.heroDetail
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          iconOpacity: root.state === "disconnected" || root.state === "loggedOut" ? 0.5 : 1.0
          iconComponent: Component {
            PangolinIcon {
              iconSize: Style.font.display
              busy: root.busy
            }
          }
        }

        Row {
          spacing: Style.space(6)

          Button {
            text: root.busy ? Model.stateLabel(root.state)
              : root.state === "loggedOut" ? "Log in"
              : root.status.running ? "Disconnect"
              : "Connect"
            bordered: true
            enabled: !root.busy && !!root.service
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily

            onClicked: {
              if (root.state === "loggedOut") root.service.login(root.hostHint)
              else if (root.status.running) root.service.disconnect()
              else root.service.connect()
            }
          }

          Button {
            visible: !!root.service && root.service.loggedIn
            text: "Log out"
            bordered: true
            enabled: !root.busy && !!root.service
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily

            onClicked: root.service.logout()
          }

          Button {
            text: "Logs"
            bordered: true
            enabled: !root.busy && !!root.service
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily

            onClicked: root.service.openLogs()
          }
        }

        Text {
          visible: root.state === "connecting"
          width: parent.width
          text: "Finish sudo/FIDO in the floating terminal."
          color: root.dimForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Text {
          visible: root.state === "loggedOut" && root.busy
          width: parent.width
          text: "Finish SSO in the floating terminal."
          color: root.dimForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Column {
          visible: root.status.peers.length > 0
          width: parent.width
          spacing: Style.space(6)

          Repeater {
            model: root.status.peers

            delegate: Item {
              required property var modelData
              width: parent.width
              implicitHeight: Math.max(peerName.implicitHeight, peerDetail.implicitHeight)

              Rectangle {
                width: Style.space(6)
                height: width
                radius: width / 2
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                color: parent.modelData.connected ? Color.accent : root.dimForeground
              }

              Text {
                id: peerName
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.leftMargin: Style.space(14)
                anchors.right: peerDetail.left
                anchors.rightMargin: Style.space(8)
                text: parent.modelData.name
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }

              Text {
                id: peerDetail
                textFormat: Text.PlainText
                anchors.right: parent.right
                text: parent.modelData.rttMs + " ms · " + parent.modelData.mode
                color: root.dimForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          visible: root.status.error !== "" || root.problem !== ""
          width: parent.width
          text: (root.status.error !== "" ? root.status.error : root.problem)
            + (Model.sessionExpired(root.status.error) ? " — log in again" : "")
          color: root.bar ? root.bar.urgent : Color.urgent
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        PanelSeparator {
          foreground: root.contentForeground
        }

        PanelSectionHeader {
          text: "DNS & ROUTING"
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
        }

        Toggle {
          width: parent.width
          label: "Override DNS"
          description: "Resolve Pangolin aliases with the client's DNS"
          checked: root.prefs.overrideDns
          enabled: !root.busy && !!root.service
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily

          onClicked: root.service.setPref("up.override_dns", root.prefs.overrideDns ? "false" : "true")
        }

        Toggle {
          width: parent.width
          label: "DNS over tunnel"
          description: "Send DNS queries through the tunnel to the upstream server"
          checked: root.prefs.tunnelDns
          enabled: !root.busy && !!root.service
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily

          onClicked: root.service.setPref("up.tunnel_dns", root.prefs.tunnelDns ? "false" : "true")
        }

        Toggle {
          width: parent.width
          label: "Prefer local routes"
          description: "Local network wins over overlapping tunnel routes"
          checked: root.prefs.preferLocalRoutes
          enabled: !root.busy && !!root.service
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily

          onClicked: root.service.setPref("up.prefer_local_routes", root.prefs.preferLocalRoutes ? "false" : "true")
        }

        Text {
          text: "Upstream DNS (comma separated, blank = system DNS)"
          color: root.dimForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
        }

        TextField {
          id: upstreamField
          width: parent.width
          text: root.prefs.upstreamDns
          placeholderText: "10.0.0.53, 1.1.1.1"
          enabled: !root.busy && !!root.service
          foreground: root.contentForeground
          font.family: root.contentFontFamily

          onEditingFinished: root.commitList("up.upstream_dns", text)
        }

        Text {
          text: "Match domains (comma separated, blank = all)"
          color: root.dimForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
        }

        TextField {
          id: matchField
          width: parent.width
          text: root.prefs.matchDomains
          placeholderText: "*.internal, corp.example.com"
          enabled: !root.busy && !!root.service
          foreground: root.contentForeground
          font.family: root.contentFontFamily

          onEditingFinished: root.commitList("up.match_domains_dns", text)
        }

        Text {
          text: "Changes apply on the next connect."
          color: root.dimForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
