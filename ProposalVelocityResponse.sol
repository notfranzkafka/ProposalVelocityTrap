// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract ProposalVelocityResponse {
    // event emitted when the trap fires
    event ProposalVelocityAlert(
        uint256 proposalsCreated,
        uint256 windowSeconds,
        uint256 latestProposalCount,
        address triggeredBy
    );

    // Example response function signature the drosera.toml will use:
    // respondToProposalVelocity(uint256,uint256,uint256)
    // - proposalsCreated: how many proposals in the sampled window
    // - windowSeconds: how many seconds that window lasted
    // - latestProposalCount: latest absolute proposalCount read
    function respondToProposalVelocity(uint256 proposalsCreated, uint256 windowSeconds, uint256 latestProposalCount) external {
        // Primary PoC action: emit an on-chain alert so it's recorded and easy to query.
        emit ProposalVelocityAlert(proposalsCreated, windowSeconds, latestProposalCount, msg.sender);

        // OPTIONAL: if you control a governance role, you could attempt to call into governance
        // to temporarily raise the cost to create new proposals. Most DAOs will NOT allow this
        // from an arbitrary response contract, so leave it as a manual/admin action.
        //
        // Example (commented out):
        // IGovernance(governance).setProposalCreationFee(newFee); // <-- only if you have authority
    }
}
