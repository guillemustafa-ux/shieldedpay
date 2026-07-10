// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {PrivacyPool} from "../src/PrivacyPool.sol";
import {ASP} from "../src/ASP.sol";

/// @title PublishRoot — publica la association root vigente (flujo operador ASP)
/// @notice Para depósitos de usuarios REALES (no demo): tras nuevos depósitos, el
///         owner del ASP corre esto para publicar la raíz de estado vigente como
///         association root válida, habilitando su retiro. Modela el flujo del
///         operador del ASP: en Privacy Pools real el ASP screenea los depósitos
///         y publica raíces periódicamente. Acá el association set == árbol de
///         estado (simplificación documentada), así que publicamos getLastRoot().
///
///         Corré:
///           forge script script/PublishRoot.s.sol:PublishRoot \
///             --rpc-url sepolia --broadcast -vvvv
///         Requiere en env: POOL_ADDRESS, ASP_ADDRESS y PRIVATE_KEY (owner del ASP).
///
/// @dev Mismo parseo de PRIVATE_KEY que DeployPool (acepta con/sin prefijo "0x").
contract PublishRoot is Script {
    function run() external {
        // Acepta PRIVATE_KEY con o sin prefijo "0x" (igual que DeployPool).
        string memory pkStr = vm.envString("PRIVATE_KEY");
        if (bytes(pkStr).length == 64) {
            pkStr = string.concat("0x", pkStr);
        }
        uint256 pk = vm.parseUint(pkStr);

        PrivacyPool pool = PrivacyPool(vm.envAddress("POOL_ADDRESS"));
        ASP asp = ASP(vm.envAddress("ASP_ADDRESS"));

        uint256 root = pool.getLastRoot();

        vm.startBroadcast(pk);
        asp.publishAssociationRoot(root);
        vm.stopBroadcast();

        console.log("Association root publicada por el ASP:", root);
    }
}
