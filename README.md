# Daccord

A free, open-source chat app for communities. Connect to one or more [accordserver](https://github.com/DaccordProject/accordserver) instances and chat in real time with your friends, teammates, or community.

## Features

- **Real-time messaging** -- Send, edit, delete, and reply to messages instantly over WebSocket
- **Channels & DMs** -- Organize conversations into channels or message people directly
- **Multi-server** -- Connect to multiple servers at the same time
- **Emoji** -- Unicode and custom server emoji with a built-in picker
- **Server admin tools** -- Manage channels, roles, bans, invites, and custom emoji
- **Responsive** -- Works on wide monitors and narrow windows alike
- **Dark theme** -- Easy on the eyes, right out of the box

## Install

Head to the [Releases](https://github.com/DaccordProject/daccord/releases) page and download the latest version for your platform:

| Platform | Download |
|---|---|
| Linux (x86_64) | `daccord-linux-x86_64.tar.gz` |
| Linux (ARM64) | `daccord-linux-arm64.tar.gz` |
| Windows (installer) | `daccord-windows-x86_64-setup.exe` |
| Windows (portable) | `daccord-windows-x86_64.zip` |

### Linux

Copy and paste this into a terminal to install the latest version:

```bash
curl -sL https://raw.githubusercontent.com/DaccordProject/daccord/master/install.sh | bash
```

This will download the latest release for your architecture, install it to `~/.local`, and add a desktop menu entry. After it finishes, you can launch Daccord from your app menu or by running `daccord` in a terminal.


### Windows

**Installer:** Download and run `daccord-windows-x86_64-setup.exe`. It will install Daccord to Program Files and add a Start Menu shortcut.

**Portable:** Download and extract `daccord-windows-x86_64.zip`, then double-click `daccord.exe` to launch.

> macOS support is planned -- stay tuned.

## Getting started

When you first open Daccord, the window will be empty. To start chatting:

1. Click the **+** button in the server bar on the left
2. Enter your server URL (for example: `chat.example.com#general?token=your-token`)
3. That's it -- you'll be connected and can start chatting right away

You can add as many servers as you like. Need a server to connect to? Check out [accordserver](https://github.com/DaccordProject/accordserver) to host your own.

## Building from source

Daccord is built with [Godot 4.6](https://godotengine.org/). To run it from source:

1. Install [Godot 4.6](https://godotengine.org/download/)
2. Clone this repository
3. Open the project in Godot and hit Play

## Contributing

Contributions are welcome! Feel free to open an issue or submit a pull request.

## License

[MIT](LICENSE)
