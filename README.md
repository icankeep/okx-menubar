# okx-menubar

A native macOS menu bar app for monitoring OKX perpetual swap prices, candlestick charts, and current positions.

> This is an unofficial OKX utility for personal use. It is not affiliated with OKX.

![OKXMenuBar screenshot](assets/okx-menubar.png)

## Features

- Real-time OKX perpetual swap quotes in the macOS menu bar
- Supports `BTC-USDT-SWAP`, `ETH-USDT-SWAP`, and `SOL-USDT-SWAP`
- Popup view with 15m and 4H candlestick charts
- Current perpetual positions via OKX private REST API
- Position polling every 30 seconds when API credentials are configured
- Left click to open the popup, right click for **Settings** / **Quit**
- Opening the popup refreshes only the **currently selected contract** candlestick data
- Switching tabs refreshes only the newly selected contract candlestick data

## Screenshot

The app lives in the macOS menu bar and shows:

- BTC / ETH headline prices in the status item
- ticker cards for supported contracts
- current positions
- 15m / 4H candlestick charts

## Requirements

- macOS 13+
- Xcode Command Line Tools
- Swift 5.9+
- Network access to `https://www.okx.com`

## Quick Start

### Run in development mode

```bash
swift run OKXMenuBar
```

After launch, the app appears in the macOS menu bar.

### Build a `.app` bundle

```bash
make app
open .build/OKXMenuBar.app
```

The generated app bundle is located at:

```text
.build/OKXMenuBar.app
```

`Info.plist` is configured with `LSUIElement=true`, so the app runs as a menu bar utility without a Dock icon.

## Usage

- **Left click** the status item to open the popup
- **Right click** the status item to open the menu
  - **Settings**
  - **Quit**
- The popup automatically refreshes the K-line data for the currently selected contract
- The popup is sized to show the full content whenever possible, instead of forcing a scroll view by default

## Configure OKX Read-Only Credentials

Position data requires OKX private API access.

Use a **read-only** OKX API key. Do **not** use a key with trading or withdrawal permissions.

### Option 1: configure from the app UI

Right click the menu bar item and open **Settings**, then fill in:

- API Key
- Secret Key
- Passphrase

The credentials are saved to:

```text
~/.okx-menubar.json
```

The file permission is set to `600` by the app.

### Option 2: create the config file manually

```bash
cat > ~/.okx-menubar.json <<'JSON'
{
  "apiKey": "your OKX API key",
  "secretKey": "your OKX secret key",
  "passphrase": "your OKX API passphrase"
}
JSON
chmod 600 ~/.okx-menubar.json
```

### Option 3: use environment variables

```bash
OKX_API_KEY=xxx \
OKX_SECRET_KEY=xxx \
OKX_PASSPHRASE=xxx \
swift run OKXMenuBar
```

## Supported Contracts

The default contracts are defined in:

```text
Sources/OKXMenuBar/Models.swift
```

Current defaults:

- `BTC-USDT-SWAP`
- `ETH-USDT-SWAP`
- `SOL-USDT-SWAP`

You can add more contracts by editing `Contract.defaults`.

## Position Quantity Notes

OKX returns perpetual position size in **contracts** (`pos`), not always in base asset units directly.

This app converts the returned size using the contract value (`ctVal`) so positions are displayed in asset units such as:

- `5.74 ETH`
- `0.12 BTC`
- `35 SOL`

## Development

Useful commands:

```bash
swift run OKXMenuBar
make build
make app
make clean
```

There is also a helper script:

```bash
./scripts/run-app.sh
```

## Security

- This repository should not contain real API credentials
- Local credentials are loaded from environment variables or `~/.okx-menubar.json`
- Do not copy your personal credential file into the repository directory
- Before publishing, make sure `.build/` and other local artifacts are excluded from git

## License

You can add a license file before publishing to GitHub, for example MIT.
