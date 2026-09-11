# OmaPangolin

OmaPangolin puts the Pangolin CLI client in the Omarchy bar. The button shows tunnel state. Its panel can connect, disconnect, log in with device-code SSO, log out, show peers, follow the client log, and edit DNS and routing preferences.

## Requirements

- The `pangolin` CLI, installed with Pangolin's official one-line installer
- `jq`

Connect and login open an Omarchy floating terminal. `pangolin up` needs sudo to create the WireGuard interface, including a FIDO touch when configured. The login flow uses terminal forms. The plugin never runs sudo from QML.

On the first connection, `pangolin up` writes `/etc/pangolin/platform_fingerprint` under sudo.

## Install

```bash
omarchy plugin add https://github.com/TerrifiedBug/omapangolin.git --enable
```

Set `host` in the widget settings if you want the first login to skip Pangolin's hosting prompt. After an account has been created, the plugin uses the host retained by the Pangolin CLI.

## Controls

Left-click opens the panel. Right-click connects or disconnects when you're logged in. Connect and login continue in the floating terminal. Disconnect and logout run without one.

The DNS and routing controls map directly to these CLI settings:

- `up.override_dns`
- `up.tunnel_dns`
- `up.prefer_local_routes`
- `up.upstream_dns`
- `up.match_domains_dns`

The plugin writes them with `pangolin config set`. Changes take effect on the next connection.

## IPC

```bash
omarchy-shell omapangolin status
omarchy-shell omapangolin connect
omarchy-shell omapangolin disconnect
omarchy-shell omapangolin login
omarchy-shell omapangolin logout
```

## Privacy and logs

Pangolin stores account secrets in `~/.config/pangolin/accounts.json`. The plugin passes that file through `jq`, which emits only the account host, email, name, organization, and whether a session exists. The session token and OLM secret never enter QML.

The client log is `~/.config/pangolin/logs/client.log`. The Logs button opens a floating terminal running `pangolin logs client -f -n 50`.
