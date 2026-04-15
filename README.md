# Accounts

Native macOS SwiftUI app for tracking personal cash and investments in one place, with GBP as the headline reporting currency.

## What It Does

- Tracks UK bank accounts through TrueLayer Open Banking
- Tracks investment accounts from either:
  - CSV files as the account source of truth
  - SnapTrade sync for supported brokerages
- Prices equities, ETFs, and funds with Financial Modeling Prep
- Converts non-GBP holdings to GBP for portfolio totals
- Shows per-account detail and a combined overview

Current account sources:

- `TrueLayer`: bank/current accounts
- `CSV File`: investment and fund accounts
- `SnapTrade`: supported brokerage investment accounts

## Current Model

### Bank accounts

- A bank connection is stored as one app account
- Multi-currency balances remain grouped under that account
- The headline value is converted to GBP
- Account detail shows:
  - per-currency balances
  - recent transactions

### Investment accounts

- Holdings and cash are stored separately
- Headline value is shown in GBP
- Mixed-currency accounts also show the original currency breakdown
- For CSV-backed accounts, the CSV is the source of truth and can be re-imported

## Requirements

- macOS 14+
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Credentials

Credentials are entered in-app via `Settings` and stored locally in:

- `~/Library/Application Support/Accounts/credentials.json`

They are not committed to the repo.

Supported credentials:

- `FMP API Key`
- `TrueLayer Client ID`
- `TrueLayer Client Secret`
- `SnapTrade Client ID`
- `SnapTrade Consumer Key`

## Build

The checked-in source of truth is `project.yml`. Generate the Xcode project first:

```sh
xcodegen generate
```

Build from the command line:

```sh
xcodebuild -project Accounts.xcodeproj -scheme Accounts -destination 'platform=macOS' build
```

Release build:

```sh
xcodebuild -project Accounts.xcodeproj -scheme Accounts -configuration Release -destination 'platform=macOS' build
```

Open in Xcode:

```sh
open Accounts.xcodeproj
```

## Running

Run from Xcode, or launch the built app from DerivedData after a successful build.

The app uses a custom URL scheme for auth callbacks:

- `accounts://truelayer-callback`
- `accounts://snaptrade-callback`

## Install

For personal use on the same Mac, build `Release` and copy `Accounts.app` into `/Applications`.

The app's data is stored outside the app bundle, so replacing the installed app does not remove:

- `~/Library/Application Support/default.store`
- `~/Library/Application Support/Accounts/credentials.json`

Those files contain your local data and credentials and are not affected by replacing `/Applications/Accounts.app`.

## Data Storage

SwiftData store:

- `~/Library/Application Support/default.store`

Debug log:

- `~/Library/Application Support/Accounts/debug.log`

Debug logging is disabled by default. To enable it for a debug run:

```sh
ACCOUNTS_DEBUG_LOG=1
```

The repo ignores local credentials, logs, and store files via `.gitignore`.

## CSV Import

CSV-backed investment accounts are intended to use one file per account as the persistent source of truth.

At a high level:

- holdings are imported into the account
- cash lines are supported
- prices are refreshed separately from FMP

The current parser is built around the app's account import flow rather than a public CSV spec document, so if the format changes, inspect:

- `Accounts/Services/CSVParser.swift`
- `Accounts/Services/PortfolioImportService.swift`

## Project Structure

- `Accounts/AccountsApp.swift` - app entry point, model container, callback wiring
- `Accounts/Models/` - SwiftData models
- `Accounts/Services/` - TrueLayer, SnapTrade, pricing, CSV import, syncing
- `Accounts/Views/` - SwiftUI screens
- `Accounts/Utilities/` - formatting, debug logging, store backup
- `AccountsTests/` - unit tests

## Notes

- This is a personal-use app, not a production product
- Some external integrations are intentionally lightweight and rely on local credentials and local persistence
- The repo is safe to publish as code, but the app still uses local filesystem storage for secrets and data
