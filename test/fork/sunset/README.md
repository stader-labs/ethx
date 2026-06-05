# ethX Sunset Fork Tests

Mainnet fork tests that exercise every step of the ethX runoff against real on-chain state before the multisig signs anything. 14 test contracts, 67 tests.

## Run

```bash
ETH_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/<KEY> \
FORK_BLOCK=21500000 \
FOUNDRY_PROFILE=fork forge test --match-path 'test/fork/sunset/**/*.t.sol'
```

That's the whole story. Expect 67/67 green in ~10 seconds on a paid RPC.

Need a single contract? `--match-contract ArmSunsetControlsTest`. Need one test? `--match-test test_GhostBatch -vvvv`.

## The runoff in five phases

```
Phase 0   FreezeBlockSnapshot   →  PreSunsetVerification
Phase 1   ArmSunsetControls (first multisig tx)       upgrade + pause + arm 7-day timer
          ArmSunsetControlsSpotCheck                  day-of-execute drift check
Phase 2   DrainActorTemplates                         per-actor redemption flows
          ValidatorExitCascade                        beacon-exit cascade (mocked)
          GhostOperatorSettlement                     adminSettleOperator batch
Phase 3   OracleDecommissionGate  →  OpenInstantRedemption (second multisig tx)
                                                      zero out finalization delays
Phase 4   OpenRedemptionHealthChecks                  cron: every 2 weeks
Phase 5   PreSweepGates  →  CustodySweep (third multisig tx)  →  PostSweepKillSwitch
          EdgeCaseFailures                            run any time
```

## What each contract does

| Contract | Purpose |
|---|---|
| `FreezeBlockSnapshot` | Writes `snapshots/freeze-snapshot-<block>.json` of every contract's state at the freeze block |
| `PreSunsetVerification` | Sunset slots unallocated, validator counts > 0, role holders match on-chain `hasRole`, oracle cadence sane |
| `ArmSunsetControls` | First multisig tx. 7 upgrades + 2 pauses + 6 custody arms + full assertion matrix (items 1-24) |
| `ArmSunsetControlsSpotCheck` | Re-runs the assertion matrix at the execute block to catch drift between propose and execute |
| `DrainActorTemplates` | ETHx holder withdraw, SD delegator withdraw, operator repay, liquidation claim, vault settlement |
| `ValidatorExitCascade` | End-to-end validator exit for one operator. Mocks the beacon side via `vm.deal` + oracle quorum |
| `GhostOperatorSettlement` | Loops `adminSettleOperator` over the sheet's `ghostBatch` slice. 25M gas ceiling, writes `ghost-batch-gas-report.json` |
| `OracleDecommissionGate` | Oracle has zero trusted nodes, historical members untrusted, non-trusted submitters revert |
| `OpenInstantRedemption` | Second multisig tx. Flips both finalization delays to zero. Asserts events + `IdenticalValue()` revert |
| `OpenRedemptionHealthChecks` | Solvency invariants for SSPM + SDUtilityPool, top-N holder redemption sims |
| `PreSweepGates` | Zero-balance sweeps revert, in-flight withdraw across boundary reverts, PLP residual within dust limit |
| `CustodySweep` | Third multisig tx. Nine sweep calls in plan order, asserts `SweptToCustody` events + master invariant |
| `PostSweepKillSwitch` | 29 guarded entry points all revert with `AssetCustodied()` |
| `EdgeCaseFailures` | Reverting custody recipient, zero-address custody, treasury underfunded, oracle spike, flip-before-decommission |

## Runoff sheet

`fixtures/runoff-sheet.json` is the single source of truth for actor addresses. Loaded once by every test via `helpers/CompanionSheet.sol`.

Six slices: `operators`, `ethxHolders`, `sdDelegators`, `roleHolders`, `custody`, `ghostBatch`. A `counts` object at the top mirrors each slice length — the Solidity loader uses it to size arrays. **Keep `counts` in sync with the array lengths** or rows get dropped.

To refresh on-chain values (current top ETHx holders, currently-trusted oracle nodes, current ghost candidates), the scan scripts live in this repo's git history and the chat thread that built this suite. The patterns are short — `cast logs` to discover candidates, `xargs -P32` to parallelize per-operator queries.

## Layout

```
test/fork/sunset/
├── *.t.sol            14 test contracts (one per phase step)
├── helpers/           Solidity helpers (sheet loader, prank wrappers, base contract)
├── fixtures/          runoff-sheet.json
├── layouts/           forge inspect storage-layout JSON for the 6 upgraded contracts
├── snapshots/         test output: freeze-snapshot-<block>.json, ghost-batch-gas-report.json
└── README.md          this file
```

## Notes worth knowing

**Fork block predates the runoff.** Default `FORK_BLOCK=21500000` is from December 2024, before any sunset code touched mainnet. Tests that need post-upgrade state call `_upgradeAllProxies(sheet)` in `setUp` to upgrade in-place.

**Oracle decommission is mocked.** The live oracle still has 3 trusted nodes. `OracleDecommissionGate` and `OpenInstantRedemption` mock `trustedNodesCount → 0` in `setUp` so they pass against today's mainnet. Set `STRICT_LIVE_ORACLE=1` to assert against true live state (will fail until ops actually decommissions the cluster).

**Role-grant fallback.** If a `roleHolders` row doesn't actually hold the role on-chain, `_asDefaultAdmin` grants it via `vm.store` so individual tests still demonstrate the flow. The mismatch is caught loudly by `PreSunsetVerification.test_RoleHoldersReconciledOnChain`.

**`deal()` for synthetic balances.** Tests that exercise redemption paths mint balances via Foundry's `deal()` rather than depending on the sheet holder still holding the token at the fork block.
