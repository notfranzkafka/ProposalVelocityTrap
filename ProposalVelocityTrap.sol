// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ITrap} from "drosera-contracts/interfaces/ITrap.sol";

/// @notice Exact Lido Aragon Voting proxy address (settable).
/// Interface adapted to the Aragon TokenVoting-like API used by Lido:
interface ILidoAragonVoting {
    /// many Aragon voting implementations expose a proposalCount() that is monotonic
    function proposalCount() external view returns (uint256);

    // optional helpful reads (not required, but included for completeness)
    function getProposal(uint256 _proposalId) external view returns (bytes memory);
}

contract ProposalVelocityTrap is ITrap {
    address public owner;
    address public governance = 0x3DF09262F937a92b9d7CC020e22709b6c6641d7d; // Lido Aragon Voting proxy
    uint256 public sampleWindow;
    uint256 public proposalsThreshold;

    constructor() {
        owner = msg.sender;
        sampleWindow = 5;
        proposalsThreshold = 3;
    }

    modifier onlyOwner() { require(msg.sender == owner, "only owner"); _; }

    function setGovernance(address _governance) external onlyOwner {
        governance = _governance;
    }

    function updateParameters(uint256 _sampleWindow, uint256 _proposalsThreshold) external onlyOwner {
        require(_sampleWindow >= 2 && _sampleWindow <= 100, "sampleWindow out of range");
        sampleWindow = _sampleWindow;
        proposalsThreshold = _proposalsThreshold;
    }

    /**
     * Updated collect(): use try/catch when calling external governance contract
     * so collect() will not revert if the external call fails. Returns (count, ts).
     */
    function collect() external view returns (bytes memory) {
        if (governance == address(0)) {
            return abi.encode(uint256(0), block.timestamp);
        }

        uint256 count = 0;
        // call proposalCount with try/catch to avoid bubbling up reverts from the target contract
        try ILidoAragonVoting(governance).proposalCount() returns (uint256 c) {
            count = c;
        } catch {
            // If the external call fails, default to 0 (avoid revert)
            count = 0;
        }

        uint256 ts = block.timestamp;
        return abi.encode(count, ts);
    }

    // ITrap declares shouldRespond as `pure`, so this implementation is pure
    // and therefore does not read contract state. It uses local defaults instead.
    function shouldRespond(bytes[] calldata data) external override pure returns (bool, bytes memory) {
        if (data.length < 2) {
            return (false, abi.encode(uint256(0), uint256(0), uint256(0)));
        }

        uint256 length = data.length;

        // local defaults (keeps function pure)
        uint256 maxWindow = 5;
        uint256 threshold = 3;

        if (length > maxWindow) length = maxWindow;

        (uint256 newestCount, uint256 newestTs) = abi.decode(data[0], (uint256, uint256));
        (uint256 oldestCount, uint256 oldestTs) = abi.decode(data[length - 1], (uint256, uint256));

        uint256 proposalsCreated = 0;
        if (newestCount >= oldestCount) proposalsCreated = newestCount - oldestCount;

        uint256 windowSeconds = 0;
        if (newestTs >= oldestTs) windowSeconds = newestTs - oldestTs;

        if (proposalsCreated >= threshold) {
            return (true, abi.encode(proposalsCreated, windowSeconds, newestCount));
        } else {
            return (false, abi.encode(uint256(0), uint256(0), newestCount));
        }
    }
}
