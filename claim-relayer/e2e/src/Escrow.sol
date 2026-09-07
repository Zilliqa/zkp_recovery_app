// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Groth16Verifier} from "./verifier.sol";

// Faithful test escrow: lodge()/claim()/balances mirror zq2 escrow_v1.sol, minus the UUPS/proxy
// machinery (deployment plumbing, tested on devnet). claim() calls the STOCK verifier via an external
// self-call (this.verifyProof) only so its assembly `return` yields a correct bool — the real escrow
// uses the integrated `internal verifyProof`. The logic (domain check, verify, balance move) is identical.
contract Escrow is Groth16Verifier {
    mapping(address => uint256) public balances;

    event Deposited(address indexed from, uint256 amount);
    event Released(address indexed src, address indexed dst, uint256 amount);

    receive() external payable {}

    // Real lodge(): credits msg.sender. In the test we impersonate the legacy address to call this.
    function lodge() external payable {
        balances[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    function claim(
        uint256[2] calldata pA,
        uint256[2][2] calldata pB,
        uint256[2] calldata pC,
        uint256[4] calldata pubSignals
    ) public {
        require(pubSignals[2] == block.chainid, "Invalid domain");
        address srcAddress = address(uint160(pubSignals[0]));
        uint256 amount = balances[srcAddress];
        bool verify = this.verifyProof(pA, pB, pC, pubSignals);
        require(verify, "Zk-proof failed");
        balances[srcAddress] = 0;
        address dstAddress = address(uint160(pubSignals[1]));
        (bool sent, ) = payable(dstAddress).call{value: amount}("");
        require(sent, "Transfer failed");
        emit Released(srcAddress, dstAddress, amount);
    }
}
