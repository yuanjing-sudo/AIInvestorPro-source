# Audit: legacy `AIInvestorPro` target

**Reviewed:** branch `main` (tip `fa8c7a6`), 32 Swift files under `Sources/AIInvestorPro`.
**Method:** static review of every file, cross-checking declarations and call sites. No
Swift toolchain was available in the review environment (Termux/Android), so nothing below
is a compiler transcript. Line numbers refer to that commit.

## TL;DR

At audit time the legacy app target **did not compile**. The problems were not isolated:
missing imports, undeclared types and members, duplicate declarations, invalid Swift
syntax, and immutable-value mutation were spread across every layer (app, domain,
analysis, LLM, risk, trading, services). The `feature/investor-kit` branch contains a
repair of those findings, now compiler-verified by green Swift CI on macOS and Linux (see
“Remediation status” below).

The new `InvestorKit` target deliberately does not depend on any of this code. It is a
clean, tested reference implementation of the quantitative pieces (indicators, risk,
backtesting, optimization, tax lots, alerts, screening, persistence, export).

Severity scale: **P0** = target cannot build; **P1** = builds but produces wrong results or
is unsafe; **P2** = architecture, testing, performance, or product quality.

## Remediation status (`feature/investor-kit`)

The findings below are preserved as the original audit. The `feature/investor-kit` branch
now contains a repair pass, a dependency-free `InvestorKit` library, and a cross-platform
PWA. The repair was written without a local Swift toolchain, then compiler-verified by the
`Swift` workflow (run
[`42169033915`](https://github.com/yuanjing-sudo/AIInvestorPro-source/actions/runs/42169033915)):
`swift build` and `swift test` pass for `InvestorKit` on Linux with Swift 5.10, and the
legacy target builds and runs the `InvestorKitTests` filter on `macos-15`.

| Original finding | Status after repair |
| --- | --- |
| Missing `import Combine` (P0.1) | Fixed in all listed files; `Portfolio` is now an `ObservableObject` class. |
| Duplicate `TradeSignal`; duplicate sizing methods (P0.2) | Consolidated to one `TradeSignal`; each sizing type has exactly one protocol method. |
| Undeclared symbols: `MACDSignal`, `absoluteValue`, `mean`, `formattedCurrency`, `replacingUnderscoresWithSpaces`, `Market.Regime`, `cloves`, undefined `gains`/`losses`, `Order.entryPrice`/`duration` (P0.3) | Fixed by shared helpers, corrected call sites, a computed `Order.duration`, and a rewritten `StockAnalyzer`. |
| Invalid syntax in `AlphaFactors`, `Setups`, `NNModel`, `PatternRecognitionModel`, `SentimentAnalysis`, `Pairs`, `RiskManager`, `SignalGenerator`, `BacktestEngine` (P0.4) | Alpha factors are reference types; setup registry uses value descriptors; malformed extensions and expressions removed. |
| Immutable values mutated (P0.5) | `Holding`, `TradeRecord`, and `Alert` trigger fields are mutable; position reduction uses arithmetic instead of `remove`. |
| Model/API mismatches (P0.6) | `Screener` API aligned; duplicate-symbol scans deduplicated by best score; short/empty inputs return neutral scans. |
| Indicator math (P1.1–P1.6) | SMA guard and EMA weighting corrected; Wilder RSI/ATR; MACD signal line computed from EMA series; short histories use neutral defaults. |
| Portfolio accounting (P1) | Weighted average cost, cost-basis denominator, cash-inclusive return denominator, and documented neutral volatility/beta. |
| Backtesting P&L/slippage/force unwraps (P1) | Deterministic fixed slippage, commission-aware P&L, net sell P&L, safe empty metrics; next-bar timing remains the caller's responsibility. |
| Yahoo timestamps and randomness (P1) | Timestamps use one anchor; synthetic values are deterministic by symbol and explicitly documented as demo data. The HTTP/rate-limit path is still non-networking. |
| Alerts compilation/crossing/re-firing (P1) | Trigger fields are assignable; `crossAbove`/`crossBelow` compare against the previous observed price; fired alerts stay fired until cleared. |
| Screener duplicates/units/edges (P1) | Best-per-symbol dedupe, percent-consistent momentum, guards for short histories, and `horizon` is a lookback only. |
| Concurrency/state (P1) | `MarketPipeline` and `ExecutionManager` are `@MainActor`; progress has a single source; execution is deterministic paper-fill. |
| CI/tests (P2) | 41 XCTest cases, 82 web unit tests, a JSDOM UI smoke test, and green Swift CI on Linux + macOS. |

**Still open / deliberately deferred:** next-bar execution inside the legacy
`BacktestEngine` API, a true actor or lock around
`YahooService` rate limiting, `@MainActor` isolation for every LLM registry, stable
`Holding.id` values across reconstruction, real market-data adapters, and the P2
architecture/security/UX items listed later in this document.

## Scorecard

| Area | State | Notes |
| --- | --- | --- |
| Compilation | **Broken** | See P0 list below; errors in at least 20 files |
| Technical indicators | **Mostly wrong** | Inverted guards, reversed EMA weighting, non-Wilder RSI, off-by-one ATR |
| Portfolio accounting | **Wrong + non-compiling** | Immutable fields mutated; average cost not updated; wrong return denominator |
| Backtesting | **Non-compiling + incorrect P&L** | Immutable `TradeRecord` fields mutated; no next-bar execution; force unwraps |
| Risk / position sizing | **Non-compiling** | Duplicate methods, invalid matrix literal, protocol mismatches |
| Market data | **Fabricated data** | `YahooService` generates random prices and malformed timestamps |
| Concurrency | **Unsafe** | `@Published` mutated from detached `Task`; no `@MainActor` isolation |
| Tests / CI | **None** | No test target, no workflows, no README (before this change) |
| Security / privacy | **No secrets handling** | No networking auth, no input limits on LLM prompts, no data-retention policy |
| UX | **Placeholder values** | Volatility hard-coded to `0.1`; beta hard-coded to `1.0` |

## P0 — build blockers

### 1. Missing `import Combine`

These files use `ObservableObject` and/or `@Published` with only `import Foundation`:

- `Sources/AIInvestorPro/Analysis/AlertsModule.swift`
- `Sources/AIInvestorPro/Domain/AlphaFactors.swift`
- `Sources/AIInvestorPro/Domain/Setups.swift`
- `Sources/AIInvestorPro/LLM/ClusteringModel.swift`
- `Sources/AIInvestorPro/LLM/ForecastingModel.swift`
- `Sources/AIInvestorPro/LLM/ModelInferencePipeline.swift`
- `Sources/AIInvestorPro/LLM/NNModel.swift`
- `Sources/AIInvestorPro/LLM/PatternRecognitionModel.swift`
- `Sources/AIInvestorPro/Services/MarketPipeline.swift`
- `Sources/AIInvestorPro/Trading/Execution.swift`

In addition, `App/AIInvestorProApp.swift` uses `@StateObject`/`@EnvironmentObject` with
`Portfolio`, a **struct** that does not conform to `ObservableObject`
(`Domain/Portfolio.swift:33`), and `Views.swift:175` does the same with `AlertStore`
(which is a class, but its own file does not compile).

**Fix:** add `import Combine` where needed and convert the observable models to
`@MainActor final class ... : ObservableObject`.

### 2. Duplicate type declarations

- `TradeSignal` is declared in `Analysis/BacktestEngine.swift:9` **and**
  `Domain/Pairs.swift:50` with different cases.
- `FixedFractionSizing` (and the other sizing types) define a `calculate(...)` method
  *and* later conform to `PositionSizing` with an identical `calculate(...)` signature
  (e.g. `Risk/PositionSizing.swift:56` and `:457`). That is an invalid redeclaration for
  every sizing type.

**Fix:** consolidate `TradeSignal` into one shared domain file; keep a single
`calculate(...)` per sizing type (or rename the non-protocol variants).

### 3. Undeclared or misspelled symbols

- `MACDSignal` is used at `Domain/Indicators.swift:16` but never declared.
- `Double.absoluteValue` is used at `Domain/Pairs.swift:89,126,128`; Swift only has
  `abs(_:)` (or `magnitude`).
- `Array<Double>.mean` and `.standardDeviation` are used at `Domain/Pairs.swift:75-76`
  and `Analysis/BacktestEngine.swift:250`; no such extensions exist in the target.
- `formattedCurrency` is used as a property at `Services/MarketPipeline.swift:59` and
  `Services/YahooService.swift:80`, but no such member exists (and the call is missing
  parentheses).
- `replacingUnderscoresWithSpaces` is called from `FeatureEngineering.swift:23`,
  `ModelInferencePipeline.swift:12,24`, `NNModel.swift:11`, `PatternRecognitionModel.swift:16`,
  and `Execution.swift:25,37,233`. It is only defined on the `Sentiment` enum
  (`SentimentAnalysis.swift:13`), not on `String`; the `String` extension in `NNModel`
  is syntactically invalid and the one in `Execution` is `private`, `mutating`, and
  missing its `func` declaration.
- `Market.Regime` is used at `Analysis/StockAnalyzer.swift:6`; the actual type is
  `MarketRegime` (`Domain/Regime.swift:4`).
- `snapshot.cloves` at `Analysis/StockAnalyzer.swift:22` is a typo for `closes`.
- `gains` and `losses` are used before being declared at `Analysis/StockAnalyzer.swift:78-81`;
  only `changes` exists.
- `Order.entryPrice` and `Order.duration` are used at `Trading/Execution.swift:115,208-220,232`,
  but `Order` (`Risk/RiskManager.swift:42`) has neither property.

### 4. Invalid Swift syntax / declarations

- `Domain/AlphaFactors.swift:27,42,67`: structs inherit from the struct `AlphaFactor`
  (`public struct MomentumAlpha: AlphaFactor`) and call `super.init` at `:32`.
  Structs cannot inherit.
- `Domain/Setups.swift:197`: `[Identifiable & Equatable]` is a bare existential; Swift 6
  requires `[any Identifiable & Equatable]`.
- `LLM/NNModel.swift:96-99`: `public extension String { self.replacingOccurrences(...) }`
  has no function declaration and unbalanced braces.
- `LLM/PatternRecognitionModel.swift:77`: stray `midPoint` at the end of an expression;
  `:79` and `:134` apply `?.first` to a non-optional `ArraySlice`.
- `LLM/SentimentAnalysis.swift:17-18` and `Domain/Pairs.swift:56-57`: `description`
  getters are empty, so a non-`Void` return is missing.
- `LLM/ClusteringModel.swift:180-184`: `Double.random.in(...)` is not valid Swift
  (should be `Double.random(in:)`), and `featureSet.symbol` at `:107` does not exist on
  `MarketFeatureSet`.
- `Risk/RiskManager.swift:127`: `private var correlationMatrix: [[Double]] = [:][]`
  is not a valid dictionary/array literal.
- `Analysis/SignalGenerator.swift:216`: a stray Markdown code fence (```) sits at the end
  of a Swift file.
- `Analysis/BacktestEngine.swift:125`: `(entryPrice ?? 0 + price) / 2` parses as
  `(entryPrice ?? price) / 2`, not the intended average.

### 5. Immutable values mutated

- `Domain/Portfolio.swift:50,61,69`: `Holding.quantity`, `averageCost`, and
  `currentPrice` are `let` (`:7-9`) but are mutated through `Holdings` array subscripts.
- `Analysis/BacktestEngine.swift:181-182`: `TradeRecord.pnl` and `pnlPercentage` are
  `let` (`:23-24`) and are assigned after initialization.
- `Analysis/BacktestEngine.swift:195`: `position!.remove(sharesToSell)` calls a
  non-existent method on `Double`.
- `Analysis/AlertsModule.swift:5-18,60-66`: `Alert` declares `let triggeredPrice` and
  `let triggeredAt`, but the initializer never assigns `triggeredPrice` (so it does not
  compile), and the trigger path later assigns both fields after construction. Even if
  the types were changed to `var`, the missing previous-price state means `isTriggered`
  can never become true through the current initializer.
- `Trading/Execution.swift:132`: `activeOrders[index].filledPrice = fillPrice` mutates
  a `let` property (`Risk/RiskManager.swift` declares `filledPrice` as `let`).

### 6. Model/API mismatches

- `Services/MarketPipeline.swift:175,264` call
  `Screener.scan([snapshot], horizonSetting: 5)`; the real API is
  `Screener.scan(_ snapshot: MarketSnapshot, horizon: Int)` and returns a **single**
  `SymbolScan`. `scanAll(_:horizonSetting:)` is the array version.
- `Analysis/Screener.swift:11` calls `scan(snapshot, regime:)` but `scan` only accepts
  `horizon:`.
- `Analysis/Screener.swift:17` uses
  `Dictionary(uniqueKeysWithValues:)` on scan results keyed by symbol. Duplicate symbols
  in the input **trap at runtime**; use `Dictionary(_:uniquingKeysWith:)`.
- `Analysis/Screener.swift:28,36` compute indices as
  `closes.count - min(horizon, closes.count)` and then `last!`; empty or short inputs
  crash, and negative indices are possible when `horizon > count`.

## P1 — correctness bugs

### Indicators (`Domain/Num.swift`, `Domain/Indicators.swift`)

1. **`movingAverage` guard is inverted** — `QuantCore/Num.swift:28`:
   `guard period >= values.count else { return [] }`. For any normal series
   (`period < count`) it returns an empty array; when it does run, the loop
   `for i in period..<values.count` never executes and only one value is returned.
   The guard should be `values.count >= period`.
2. **EMA weighting is reversed** — `QuantCore/Num.swift:47-55` computes
   `previous * alpha + newest * (1 - alpha)`. Convention (and `Indicators.swift:73+`)
   weights the newest observation by `alpha`. The two EMA implementations therefore
   disagree.
3. **RSI is not Wilder-smoothed** — `Domain/Indicators.swift:61-69` averages *all*
   gains/losses rather than the last `period`, and never applies Wilder smoothing.
   `StockAnalyzer.swift:75-83` repeats the mistake and also references undefined
   `gains`/`losses`.
4. **ATR is off by one** — `Domain/Indicators.swift:181-185` sets
   `start = trueRanges.count - period + 1` and then averages
   `trueRanges[start...]`, i.e. `period - 1` values instead of `period`.
5. **MACD cannot compile** (`MACDSignal` missing) and the signal line is never computed
   from the MACD line (`Indicators.swift:16-18`).
6. `TechnicalIndicators.calculate` returns a fully empty `TechnicalIndicators()` when
   `prices.count < 26` (`Indicators.swift:9`), discarding all shorter-period indicators.

`InvestorKit` has a series-aligned implementation of all of these with tests; use it as
the reference when repairing.

### Portfolio accounting (`Domain/Portfolio.swift`)

1. `add(_:)` increases `quantity` but **never recomputes `averageCost`** (`:48-54`), so
   cost basis and P&L are wrong after a second purchase.
2. `totalGainLossPercentage()` divides by `totalValue` instead of cost basis
   (`:78-82`): it measures gain over current value, not return on invested capital.
3. `totalGainLoss()` ignores cash entirely and contains a no-op
   `(cash > 0 ? 0 : 0)` (`:74-76`).
4. `totalReturn()` builds `initialValue` from *current* `cash + costBasis` (`:111-116`).
   Cash has already been reduced by purchases, so fees and realized P&L are silently
   excluded.
5. `volatility` is hard-coded to `0.1` and `beta` to `1.0` (`:87-100`); `sharpeRatio`
   is therefore not meaningful. `volatility` is also unused (`holding` is unused in the
   map), which will warn.
6. `Holding.id` is a fresh `UUID` per init (`:25`), so two holdings for the same symbol
   are not stable identifiers across reconstruction.

### Backtesting (`Analysis/BacktestEngine.swift`)

1. No next-bar execution model: signals are executed at the same bar, which leaks
   look-ahead information.
2. P&L is approximated from `capital - initialCapital` and then assigned to immutable
   fields (`:168-182`); partial exits use a different, inconsistent formula.
3. Slippage/commission math is applied inconsistently: buys multiply cost by
   `(1 + commissionPct)` while sells multiply proceeds by `(1 - commissionPct)`, and
   slippage uses `Double.random` so results are not reproducible (`:89,161`).
4. `equityCurve[0]` and `returns.reduce(...) / Double(returns.count)` crash when the
   curve has fewer than two points (`:237-250`).
5. `winningTrades`/`losingTrades` force-unwrap `pnlPercentage` (`:228-229`) even though
   open trades have `nil`.

### Market data (`Services/YahooService.swift`)

1. `generateTimestamps` (`:203-222`) subtracts `count - 1 - i` from `lastDate` on **every**
   iteration, producing cumulative, duplicated, and out-of-order dates. It should compute
   each date from a fixed anchor.
2. Historical prices are synthesized with `Double.random` (`:195-200`), not fetched. The
   service therefore looks like a live feed but returns fabricated data.
3. Rate limiting uses a `lastRequest` timestamp, but there is no async serialization
   (actor or lock), so concurrent callers can race (`:105,146`).
4. No `HTTPURLResponse` status validation on the quote path; error bodies can be parsed
   as data.

### Alerts (`Analysis/AlertsModule.swift`)

1. `AlertStore` has no previous-price state, so `crossAbove`/`crossBelow` degrade to
   `above`/`below` (`:49-56`).
2. Triggering constructs a new `Alert` without `triggeredPrice`, then attempts to assign
   it (`:60-66`), which does not compile and would keep `isTriggered` false anyway.
3. Alerts are never removed after firing and there is no cooldown, so a condition that
   remains true can re-fire on the next poll once state is reset.

### Screener (`Analysis/Screener.swift`)

1. Duplicate-symbol crash (P0 above).
2. `horizon` is reused as both a lookback and an array prefix limit
   (`scanAll` uses `snapshots.prefix(horizonSetting)`), conflating two concepts.
3. `momentumScore` is a percent change but is compared against `0.05`
   (`:45`), mixing percent and fraction units.
4. Empty/short `closes` crash on `last!` and negative indices.

## P1 — concurrency and state

- `Services/MarketPipeline.swift:81`: `MarketPipeline` is a plain `ObservableObject`.
  `start` launches a detached `Task` (`:106`) that mutates `@Published` properties
  (`:114,133,152`) without `@MainActor`; SwiftUI will update from a background thread.
- `currentStepIndex` is incremented **twice per step**: once in the loop (`:130`) and
  again inside each helper (`:153,166,182,188,203`). Progress overshoots `1.0` (for
  example `1.6` for five steps) before being reset at the end (`:134`).
- `Trading/Execution.swift`: the simulated executor mutates shared order state from an
  `async` method with no actor isolation (`:102-133`), and sleeps for 0.5 s per order.
- `LLM/*` registries expose `@Published` mutable arrays from non-`@MainActor` classes.

**Fix:** mark UI-facing models `@MainActor`, keep a single source of step progress
(remove the per-helper increments), and move execution state behind an actor.

## P2 — architecture and API

1. **No module boundaries.** UI, domain, networking, and ML code all live in one
   executable target. There is no library product to test or reuse. `InvestorKit`
   demonstrates the split; long term, move `Domain`, `QuantCore`, `Risk`, and
   `Services` into library targets and keep `App` as a thin shell.
2. **Two sources of truth for indicators.** `Num.swift` and `Indicators.swift` implement
   overlapping functions with different conventions; neither is tested.
3. **Naming and units are inconsistent.** Some functions return percent (`* 100`),
   others fractions; `momentumScore` is compared against a fraction; `formattedCurrency`
   is used as a property and a function.
4. **Force unwraps in public paths.** `last!`, `snapshot.closes.last!`, `position!`,
   `error!`, and `try!` appear in production code. `InvestorKit` uses `nil`/`Result`
   or documented defaults instead.
5. **Non-determinism in core paths.** `Double.random` is used for prices, slippage, and
   clustering, so runs cannot be reproduced or regression-tested. Use an injected seeded
   generator (`SeededGenerator` in InvestorKit).
6. **The package name and target name are identical** (`AIInvestorPro`), which makes
   `swift run` ambiguous once multiple executables exist. Consider a distinct executable
   product name (e.g. `AIInvestorProApp`).

## P2 — security and privacy

1. **No secrets management.** No networking keys are read, but there is also no
   `.env`/Keychain abstraction; if an LLM or broker key is added, it will likely be
   hard-coded. Add a `Secrets` provider backed by Keychain/`~/.config` and document it.
2. **LLM surface is unrestricted.** `LLMService` builds prompts from arbitrary strings
   with no length limits, no output validation, and no retry/cost controls. Add request
   timeouts, token caps, redaction, and structured output validation.
3. **No data-retention policy.** Portfolio and market data are kept in memory; there is
   no documented export/delete path. `InvestorKit.PortfolioStore` adds atomic JSON
   persistence with backup and delete operations as a starting point.
4. **Unofficial data source.** The Yahoo endpoint is undocumented and may be blocked or
   changed; never present it as licensed real-time data. Add a provider abstraction and
   a clear disclosure in the UI.
5. **No input validation on symbols.** `InvestorKit.YahooFinanceProvider` validates and
   percent-encodes symbols (length ≤ 24, trimmed, uppercased); the legacy service does
   not.

## P2 — testing and CI

- No test target, no fixtures, no deterministic data, no CI workflow, no coverage.
- Add at minimum:
  - an `InvestorKitTests` target (already added) and `AIInvestorProTests` once the app
    compiles;
  - GitHub Actions on macOS for SwiftUI builds and on Linux for the library;
  - `swift-format` or SwiftLint in CI;
  - a snapshot/golden test for the report renderer;
  - property tests for indicators (alignment, nil warm-up, monotonic edge cases).
- The new library tests cover SMA/EMA/RSI/ATR/MACD/Bollinger/Aroon, performance and
  drawdown math, covariance/risk contributions, VaR, optimizer constraints, Monte Carlo
  determinism, backtest execution timing, tax lots, alerts, screener behavior, CSV
  escaping, and persistence round-trips.

## P2 — performance

1. Indicators allocate a fresh array per call and repeatedly slice (`Array(slice)`) in
   loops; fine for demos, costly for screeners over thousands of symbols. Cache
   per-symbol indicator series.
2. `Screener.scanAll` calls `TechnicalIndicators.calculate` for every snapshot, then
   throws the indicators away (`MarketPipeline.calculateIndicators` separately computes
   them and discards them too). Compute once and attach to the snapshot.
3. Monte Carlo in the legacy code does not exist; `InvestorKit.monteCarlo` is O(sims ×
   days × assets²) and single-threaded. For large runs, batch paths or use
   `TaskGroup`/Accelerate.
4. `YahooService` has no caching; `InvestorKit.YahooFinanceProvider` adds a TTL cache,
   request throttling, and bounded retry with backoff.

## P2 — UX and product

1. Copy such as “Simulated” and placeholder metrics should not be presented as analysis.
   The UI shows volatility/beta values that are hard-coded.
2. Report strings mix `%` literals with `String(format:)` format specifiers. Many are
   invalid: `String(format: "%.2f%", x)` should be `"%.2f%%"` (or better, use the new
   `Double.formattedPercent`). Examples: `Analysis/BacktestEngine.swift:306-327`,
   `Analysis/ReportRenderer.swift:13-17`, `App/Views.swift:74,159`,
   `Domain/Portfolio.swift:121,127`, `Risk/PositionSizing.swift:187,249,382`,
   `Services/YahooService.swift:39,80`.
3. Some strings already append `%` outside the format call, producing `12.34%%` or a
   literal `%` with a missing argument. Normalize formatting through one helper.
4. There is no empty/error/loading state audit, no accessibility labels, and no
   localization. Add `LocalizedStringKey` and VoiceOver labels when the app builds.
5. `AlertStore.checkAlerts` loops `for snapshot in snapshots where snapshots.count > 0`
   (a constant condition) and iterates all alerts for each snapshot; it can trigger the
   same alert multiple times per pass and is O(snapshots × alerts). Pre-index by symbol.

## What is already fixed in `InvestorKit`

The new library is not just a refactor; it is a reference implementation for the repair:

- Series-aligned indicators with explicit warm-up `nil`s and tests.
- Fraction/percent conventions documented at the type level.
- Deterministic `SeededGenerator`, `MockMarketDataProvider`, and Monte Carlo.
- Next-bar-open backtesting with commission/slippage and a test that asserts execution
  timing.
- Weighted-average cost updates and lot-level tax accounting.
- A screener that reports every failed rule instead of crashing.
- Edge-triggered alerts with cooldown and one-shot behavior.
- Atomic, actor-isolated persistence with backup/delete/export.
- RFC 4180 CSV escaping and Markdown/JSON export.
- No force unwraps on user/data-driven paths; invalid input returns `nil`, `0`, or a
  typed error.

## Recommended remediation order

1. **Make it compile (PR 1).** Add imports; consolidate duplicate `TradeSignal` and
   sizing methods; fix syntax errors in `AlphaFactors`, `NNModel`, `PatternRecognitionModel`,
   `SentimentAnalysis`, `Pairs`, `RiskManager`, `Execution`; make `Portfolio` and
   `AlertStore` observable classes or remove the property wrappers.
2. **Stabilize models (PR 2).** Make `Holding.quantity/averageCost/currentPrice` `var`,
   fix `Alert` trigger fields, add `Order.entryPrice`/`duration` or change call sites,
   align `Screener`/`MarketPipeline` APIs.
3. **Fix math (PR 3).** Replace indicator implementations with the `InvestorKit`
   algorithms (or import the library), add fixtures/tests, and remove hard-coded
   volatility/beta.
4. **Replace fabricated market data (PR 4).** Back `YahooService` with
   `InvestorKit.YahooFinanceProvider` or a documented mock; never label random walks as
   live data.
5. **Concurrency + UI (PR 5).** `@MainActor` view models, single progress counter, actor
   for execution, cancellation support.
6. **Security + observability (PR 6).** Secrets abstraction, LLM limits/validation,
   logging/metrics, data export/delete.
7. **CI (PR 7).** macOS app build, Linux library tests, formatting, and a release
   checklist.

## Reproduce / verify

```bash
# Library only (no SwiftUI/Apple frameworks required)
INVESTORKIT_ONLY=1 swift build
INVESTORKIT_ONLY=1 swift test
INVESTORKIT_ONLY=1 swift run InvestorKitDemo

# Full package, including the repaired SwiftUI app target (macOS)
swift build
swift test --filter InvestorKitTests
```

The full package requires a macOS toolchain for SwiftUI. The `Swift` GitHub Actions
workflow runs both variants on every push and pull request.
