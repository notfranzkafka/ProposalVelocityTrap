# ProposalVelocityTrap

## Overview

**ProposalVelocityTrap** is a Drosera trap PoC that monitors proposal creation velocity on an Aragon TokenVoting-like governance implementation (Lido's Aragon Voting proxy by default) and triggers a response when proposal creation exceeds a configured threshold within a sampled time window.

This repository contains:

* `ProposalVelocityTrap.sol` — the trap contract implementing `ITrap` semantics (collect + shouldRespond).
* `ProposalVelocityResponse.sol` — an on-chain response contract that emits an alert when the trap fires.
* `drosera.toml` — Drosera manifest / deployment metadata.

---

## Contracts — exact signatures & behaviour

### ProposalVelocityTrap.sol (highlights)

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ITrap} from "drosera-contracts/interfaces/ITrap.sol";

interface ILidoAragonVoting {
    function proposalCount() external view returns (uint256);
    function getProposal(uint256 _proposalId) external view returns (bytes memory);
}

contract ProposalVelocityTrap is ITrap {
    address public owner;
    address public governance = 0x3DF09262F937a92b9d7CC020e22709b6c6641d7d;
    uint256 public sampleWindow;
    uint256 public proposalsThreshold;

    constructor() { ... }

    modifier onlyOwner() { ... }

    function setGovernance(address _governance) external onlyOwner { ... }

    function updateParameters(uint256 _sampleWindow, uint256 _proposalsThreshold) external onlyOwner { ... }

    function collect() external view returns (bytes memory) { ... }

    function shouldRespond(bytes[] calldata data) external override pure returns (bool, bytes memory) { ... }
}
```

**Important exact function signatures (as implemented):**

* `function collect() external view returns (bytes memory)`

  * Collects a snapshot from the configured `governance` contract. Uses `try/catch` calling `ILidoAragonVoting(governance).proposalCount()` to avoid bubbling reverts. Returns `abi.encode(uint256 count, uint256 timestamp)`.

* `function shouldRespond(bytes[] calldata data) external override pure returns (bool, bytes memory)`

  * `ITrap` expects `shouldRespond` as `pure` in this implementation. It expects the caller to provide a sequence of `collect()`-encoded snapshots in `data` (newest first at index 0). The function decodes the newest and oldest snapshots in the sampled window and computes `proposalsCreated = newestCount - oldestCount` and `windowSeconds = newestTs - oldestTs` (safely: zero if underflow). If `proposalsCreated >= threshold` it returns `(true, abi.encode(proposalsCreated, windowSeconds, newestCount))`, otherwise returns `(false, abi.encode(uint256(0), uint256(0), newestCount))`.

* Admin functions (access controlled by `onlyOwner`):

  * `function setGovernance(address _governance) external onlyOwner`
  * `function updateParameters(uint256 _sampleWindow, uint256 _proposalsThreshold) external onlyOwner`

**On-chain defaults:**

* `governance` default: `0x3DF09262F937a92b9d7CC020e22709b6c6641d7d` (Lido Aragon Voting proxy)
* `sampleWindow` default: `5`
* `proposalsThreshold` default: `3`

---

### ProposalVelocityResponse.sol (highlights)

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract ProposalVelocityResponse {
    event ProposalVelocityAlert(
        uint256 proposalsCreated,
        uint256 windowSeconds,
        uint256 latestProposalCount,
        address triggeredBy
    );

    function respondToProposalVelocity(uint256 proposalsCreated, uint256 windowSeconds, uint256 latestProposalCount) external {
        emit ProposalVelocityAlert(proposalsCreated, windowSeconds, latestProposalCount, msg.sender);
    }
}
```

**Exact response signature used in `drosera.toml`:**

* `respondToProposalVelocity(uint256,uint256,uint256)`

**Behaviour:** Emits `ProposalVelocityAlert` with the metric payload and `msg.sender` as the triggering address. The contract is intentionally minimal — it records the incident on-chain for easy querying.

---

## drosera.toml (as provided)

```toml
ethereum_rpc = "https://ethereum-hoodi-rpc.publicnode.com"
drosera_rpc = "https://relay.hoodi.drosera.io"
eth_chain_id = 560048
drosera_address = "0x91cB447BaFc6e0EA0F4Fe056F5a9b1F14bb06e5D"

[traps]

[traps.proposal_velocity]
path = "out/ProposalVelocityTrap.sol/ProposalVelocityTrap.json"
response_contract = "0x26561c4BBc07ECFdD7ea9C0Ae6B78C970574b1Ea"
response_function = "respondToProposalVelocity(uint256,uint256,uint256)"
cooldown_period_blocks = 20
min_number_of_operators = 1
max_number_of_operators = 3
block_sample_size = 6
private_trap = true
whitelist = ["0x707496D99E6d5C95291E696aBfeEf39B5116F7EA"]
address = "0x34bB9D3F1DDC683DFcF8DAfEB2e5D809e33d30d4"
```

**Notes about the manifest values:**

* `path` should match your build output path (Forge/solc JSON artifact). Adjust if you use a different build system.
* `response_contract` and `address` fields are pre-filled in the repo — update them to the actual deployed addresses if you re-deploy.
* `response_function` matches the exact response function above.
* `block_sample_size = 6` means Drosera will pass up to 6 `collect()` snapshots in the `shouldRespond(bytes[] data)` call. The contract itself caps `maxWindow = 5` within `shouldRespond` (local default) — you may wish to align these values to avoid confusion.

---

## How the data flows (operational summary)

1. Drosera coordinator calls the trap's `collect()` repeatedly over time (per operator) and stores the returned snapshot: `abi.encode(count, timestamp)`.
2. When enough samples exist, Drosera calls `shouldRespond(bytes[] calldata data)` with a slice of the latest snapshots (newest first at index 0).
3. `shouldRespond` computes proposals created in the sample window and returns a boolean and `abi.encode(...)` payload. If `true`, Drosera will call the configured `response_contract` function (as defined in `drosera.toml`) using the `bytes` return as call parameters (matching the expected signature).
4. `ProposalVelocityResponse.respondToProposalVelocity(...)` executes and emits an on-chain `ProposalVelocityAlert` event.

---

## Example `cast` / Foundry commands

**Assumptions:** Replace `<TRAP_ADDR>`, `<RESPONSE_ADDR>`, `<PRIVATE_KEY>` with actual values. These examples assume the trap was deployed with the default `collect()` and `shouldRespond` signatures.

* Set governance (admin):

```
cast send <TRAP_ADDR> "setGovernance(address)" 0x... --private-key <PRIVATE_KEY>
```

* Update parameters (admin):

```
cast send <TRAP_ADDR> "updateParameters(uint256,uint256)" 6 4 --private-key <PRIVATE_KEY>
```

* Call `collect()` (view that returns encoded bytes):

```
cast call <TRAP_ADDR> "collect()"
```

This prints the ABI-encoded `(uint256 count, uint256 timestamp)`. For integration tests, collect several snapshots and create an array of hex-encoded elements to pass to `shouldRespond`.

* Example `shouldRespond` call with two samples (manually construct):

```
# Suppose snapshot newest = abi.encode(uint256(100), uint256(1690000000)) -> 0x... (COLLECT_NEW)
# oldest = abi.encode(uint256(98), uint256(1689999400)) -> 0x... (COLLECT_OLD)
cast call <TRAP_ADDR> "shouldRespond(bytes[])" '[<COLLECT_NEW>,<COLLECT_OLD>]'
```

* Example direct call to response contract (simulate Drosera calling it):

```
cast send <RESPONSE_ADDR> "respondToProposalVelocity(uint256,uint256,uint256)" 3 600 100 --private-key <PRIVATE_KEY>
```

> Tip: Use foundry/forge tests to assemble multiple `collect()` return values and call `shouldRespond` with a constructed `bytes[]` array to fully test the logic in a local environment.

---
