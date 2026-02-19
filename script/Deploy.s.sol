// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../contracts/ECashV3.sol";

contract DeployECash is Script {
    bytes32 constant MERKLE_ROOT = 0xc06f6d42c50831eb4f10156b0668703e7032f203637401071e9cf9cad46ab7a9;

    function run() external {
        vm.startBroadcast();

        ECashV3 ecash = new ECashV3(MERKLE_ROOT);

        console.log("ECashV3 deployed to:", address(ecash));
        console.log("Owner:", ecash.owner());
        console.log("Merkle Root:", vm.toString(ecash.merkleRoot()));

        vm.stopBroadcast();
    }
}
