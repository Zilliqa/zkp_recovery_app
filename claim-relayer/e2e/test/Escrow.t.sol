// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {EscrowInit} from "../src/escrow_v1.sol";

interface Vm {
    function chainId(uint256) external;
    function deal(address, uint256) external;
    function prank(address) external;
    function readFile(string calldata) external view returns (string memory);
    function parseJsonBytes(string calldata, string calldata) external returns (bytes memory);
}

// End-to-end: impersonate the legacy (SHA-256) address -> real lodge() -> submit the EXACT app calldata
// to claim() -> assert the funds land at the newAddr baked into the proof. Runs against the REAL zq2
// escrow (src/escrow_v1.sol) + its integrated verifier (src/verifier.sol), deploying the implementation
// directly (the proxy is only needed for upgrades, which these tests don't exercise).
contract EscrowE2E {
    Vm constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    // from claim.json (proof generated with domain=32769):
    address constant OLD = 0xb413DF42a4e2D5236Fe1B914a21c354eb86F133C; // legacy addr proven
    address constant NEW = 0x00112233445566778899AABbCCdDeeFf00112233; // destination bound in the proof
    uint256 constant AMOUNT = 5 ether;

    function _calldata() internal returns (bytes memory) {
        return vm.parseJsonBytes(vm.readFile("claim.json"), ".calldata");
    }

    function test_e2e_claim_moves_funds_to_proof_destination() public {
        vm.chainId(32769); // claim() requires pubSignals[2] == block.chainid
        EscrowInit escrow = new EscrowInit();
        bytes memory cd = _calldata();

        // 1) DEPOSIT — impersonate the legacy address and call the REAL lodge()
        vm.deal(OLD, AMOUNT);
        vm.prank(OLD);
        escrow.lodge{value: AMOUNT}();
        require(escrow.balanceOf(OLD) == AMOUNT, "lodge did not credit the legacy address");
        require(NEW.balance == 0, "destination should start empty");

        // 2) CLAIM — submit the app calldata verbatim (exactly what the relayer sends)
        (bool ok, bytes memory ret) = address(escrow).call(cd);
        require(ok, string(abi.encodePacked("claim() reverted: ", ret)));

        // 3) ASSERT — funds moved to the proof-bound destination; source balance zeroed
        require(NEW.balance == AMOUNT, "funds did not reach newAddr");
        require(escrow.balanceOf(OLD) == 0, "source balance not cleared");
    }

    function test_replay_reverts_and_moves_nothing() public {
        vm.chainId(32769);
        EscrowInit escrow = new EscrowInit();
        bytes memory cd = _calldata();
        vm.deal(OLD, AMOUNT);
        vm.prank(OLD);
        escrow.lodge{value: AMOUNT}();

        (bool ok1,) = address(escrow).call(cd);
        require(ok1, "first claim failed");
        require(NEW.balance == AMOUNT, "first claim did not pay out");

        // Replay: the real escrow_v1.sol has `require(amount > 0, "No balance lodged")`, so once the
        // source balance is zeroed a re-claim REVERTS and moves nothing (no double-spend).
        uint256 beforeBal = NEW.balance;
        (bool ok2,) = address(escrow).call(cd);
        require(!ok2, "replay should revert (No balance lodged)");
        require(NEW.balance == beforeBal, "replay moved additional funds");
    }
}
