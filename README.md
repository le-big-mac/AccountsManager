# Accounts

Native macOS SwiftUI app for tracking personal cash and investments in one place, with GBP as the headline reporting currency.

## What It Does

- Tracks UK bank accounts and supported credit cards through TrueLayer Open Banking
- Tracks investment accounts from either:
  - CSV files as the account source of truth
  - SnapTrade sync for supported brokerages
- Prices equities, ETFs, and funds with Financial Modeling Prep
- Stores analyst target prices for supported stocks and ETFs via Alpha Vantage
- Converts non-GBP holdings to GBP for portfolio totals
- Shows per-account detail and a combined overview

Current account sources:

- `TrueLayer`: bank/current accounts and supported credit cards
- `CSV File`: investment and fund accounts
- `SnapTrade`: supported brokerage investment accounts

## Current Model

### Bank accounts

- A bank connection is stored as one app account
- Multi-currency balances remain grouped under that account
- The headline value is converted to GBP
- Account detail shows:
  - per-currency balances

### Credit cards

- A TrueLayer card connection is stored as one app account
- Card balances are treated as liabilities and stored as negative balances
- The headline value reduces net worth in the same way as other negative cash balances
- The connection flow is shared with bank accounts, using the provider's normal authentication and 2FA

### Investment accounts

- Holdings and cash are stored separately
- Headline value is shown in GBP
- Mixed-currency accounts also show the original currency breakdown
- For CSV-backed accounts, the CSV is the source of truth and can be re-imported
- Holdings can show open P&L percentage when an average purchase price is available
- Analyst targets are cached in shared security metadata when available

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
- `Alpha Vantage API Key`
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

The default bundle identifier in `project.yml` is `io.github.le-big-mac.accountsmanager`. If you plan to sign or distribute your own build, change it to an identifier you control.

## Running

Run from Xcode, or launch the built app from DerivedData after a successful build.

The app uses a custom URL scheme for auth callbacks:

- `accounts://truelayer-callback`
- `accounts://snaptrade-callback`

## Install

For personal use on the same Mac, build `Release` and copy `Accounts.app` into `/Applications`.

The app's data is stored outside the app bundle, so replacing the installed app does not remove:

- `~/Library/Application Support/Accounts/Accounts.store`
- `~/Library/Application Support/Accounts/credentials.json`

Those files contain your local data and credentials and are not affected by replacing `/Applications/Accounts.app`.

## Data Storage

SwiftData store:

- `~/Library/Application Support/Accounts/Accounts.store`

Legacy migrations:

- older builds may have used `~/Library/Application Support/default.store`
- current builds migrate that legacy store into the app-specific path above on launch

Debug log:

- `~/Library/Application Support/Accounts/debug.log`

Debug logging is disabled by default. To enable it for a debug run:

```sh
ACCOUNTS_DEBUG_LOG=1
```

The repo ignores local credentials, logs, and store files via `.gitignore`.

## CSV Import

CSV-backed investment accounts are intended to use one file per account as the persistent source of truth.

Current preferred format is a generic portfolio CSV with one header row and one row per holding or cash balance.

Expected columns:

- `name`
- `assetClass`
- `units`
- `currency`
- optional `averagePurchasePrice`
- optional `ticker`
- optional `isin`
- optional `sedol`

Rules:

- `assetClass` should be one of `cash`, `stock`, `etf`, `fund`, or `gilt`
- non-cash rows become holdings
- `cash` rows become cash balances
- for cash rows, the amount is stored in `units`
- `currency` is the holding price currency or the cash currency
- `averagePurchasePrice` is optional and stores per-unit cost basis for open P&L display
- `ticker`, `isin`, and `sedol` are optional, but at least one identifier is useful for live pricing
- gilt rows use `units` as nominal held and `currentCleanPrice` as the current clean price per GBP 100 nominal
- gilt HTM calculations use `dirtyPricePaid` per GBP 100 nominal as the cost basis

Example:

```csv
name,assetClass,units,currency,averagePurchasePrice,ticker,isin,sedol,currentCleanPrice,couponRate,maturityDate,settlementDate,cleanPricePaid,dirtyPricePaid,couponDates
FTSE Global All Cap Index Fund Accumulation,fund,36.9627,GBP,252.40,VAFTGAG,GB00BD3RZ582,
Apple Inc,stock,12,USD,182.15,AAPL,US0378331005,
USD Cash,cash,18003.45,USD,,,,
GBP Cash,cash,130.12,GBP,,,,
1% Treasury Gilt 2032,gilt,10000,GBP,,,,GB00BM8Z2S21,93.40,1%,2032-01-31,2026-04-29,92.80,93.15,31 Jan;31 Jul
```

For conventional gilts:

- `couponRate` is the annual coupon rate; `1%`, `1`, and `0.01` are accepted
- `maturityDate` and `settlementDate` accept `yyyy-MM-dd`, `dd/MM/yyyy`, or UK month-name dates
- `couponDates` is a semicolon-separated pair of coupon days, such as `31 Jan;31 Jul`
- displayed value is nominal held multiplied by current clean price divided by 100
- displayed returns are gross annual HTM yield and gross total HTM return if held to maturity
- HTM entitlement excludes payments where settlement is on or after the seven-business-day ex-dividend date

Other import paths still exist for older Vanguard UK, Robinhood, and Interactive Investor exports, but the generic portfolio format is the format the current app model is built around.

If the format changes in future, inspect:

- `Accounts/Services/CSVParser.swift`
- `Accounts/Services/PortfolioImportService.swift`

## CSV Export

The main window includes an `Export CSV` button that writes the current live portfolio state to one CSV file.

Export columns:

- `accountName`
- `accountType`
- `sourceType`
- `name`
- `assetClass`
- `units`
- `currency`
- `averagePurchasePrice`
- `ticker`
- `isin`
- `sedol`
- `currentCleanPrice`
- `couponRate`
- `maturityDate`
- `settlementDate`
- `cleanPricePaid`
- `dirtyPricePaid`
- `couponDates`

Notes:

- investment holdings export one row per holding
- investment cash exports as `assetClass = cash`, with the amount stored in `units`
- bank balances also export as `assetClass = cash`, one row per currency balance
- TrueLayer credit card balances export as cash liability rows, with negative values in `units`
- the extra account/source columns are informational; the current generic importer ignores them

## Analyst Targets

Analyst targets are optional enrichment for holdings with a ticker and asset class `stock` or `etf`.

- Source: Alpha Vantage `OVERVIEW`
- Stored in shared security metadata and reused until stale
- Refreshed in the background rather than blocking price updates
- Throttled and budgeted to fit the Alpha Vantage free-tier daily cap

Current refresh policy:

- if a holding has no stored target, it is eligible immediately
- if a holding has a target, it refreshes when older than 7 days
- cash and most fund/OEIC rows do not participate

## Project Structure

- `Accounts/AccountsApp.swift` - app entry point, model container, callback wiring
- `Accounts/Models/` - SwiftData models
- `Accounts/Services/` - TrueLayer, SnapTrade, pricing, CSV import, syncing
- `Accounts/Views/` - SwiftUI screens
- `Accounts/Utilities/` - formatting, debug logging, store backup

## Notes

- This is a personal-use app, not a production product
- Some external integrations are intentionally lightweight and rely on local credentials and local persistence
- The repo is safe to publish as code, but the app still uses local filesystem storage for secrets and data

## Warning

This project was built in a heavily iterative, AI-assisted way. Treat it as practical personal software, not as a polished reference implementation. Review the code carefully before extending it, publishing derivatives, or trusting it with anything important.
