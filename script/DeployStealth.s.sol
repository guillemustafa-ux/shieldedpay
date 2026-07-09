// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ERC5564Announcer} from "../src/ERC5564Announcer.sol";
import {ERC6538Registry} from "../src/ERC6538Registry.sol";

/// @title DeployStealth — despliega ERC5564Announcer + ERC6538Registry (Fase A)
/// @notice Lee la private key de variables de entorno (.env), nunca hardcodeada.
///         Corré:
///           forge script script/DeployStealth.s.sol:DeployStealth \
///             --rpc-url sepolia --broadcast --verify -vvvv
/// @dev Ambos contratos no tienen parámetros de constructor: son deploys
///      directos. `vm.envString` + normalización de "0x" igual que en
///      botpass/script/Deploy.s.sol para aceptar la PRIVATE_KEY con o sin
///      prefijo.
contract DeployStealth is Script {
    function run() external returns (ERC5564Announcer announcer, ERC6538Registry registry) {
        // Acepta PRIVATE_KEY con o sin prefijo "0x" (le agrega el 0x si falta).
        string memory pkStr = vm.envString("PRIVATE_KEY");
        if (bytes(pkStr).length == 64) {
            pkStr = string.concat("0x", pkStr);
        }
        uint256 pk = vm.parseUint(pkStr);

        vm.startBroadcast(pk);
        announcer = new ERC5564Announcer();
        registry = new ERC6538Registry();
        vm.stopBroadcast();

        console.log("ERC5564Announcer desplegado en:", address(announcer));
        console.log("ERC6538Registry desplegado en:", address(registry));
        console.log("Pega estas addresses en el README y en el frontend/dapp.");
    }
}
