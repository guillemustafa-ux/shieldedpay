// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {PrivacyPool} from "../src/PrivacyPool.sol";
import {ASP} from "../src/ASP.sol";
import {IHasher} from "../src/interfaces/IHasher.sol";

/// @title SeedDemo — siembra el pool con depósitos de demo publicables (Fase B)
/// @notice Después del deploy, este script deja la dApp DEMOSTRABLE de punta a
///         punta sin operador manual: inserta K=3 depósitos de demo cuyas notas
///         (nullifier, secret) son DETERMINISTAS y públicas, y publica la
///         association root que las incluye. Un visitante puede tomar cualquiera
///         de las 3 notas impresas y retirar desde la dApp por su cuenta.
///
///         Corré:
///           forge script script/SeedDemo.s.sol:SeedDemo \
///             --rpc-url sepolia --broadcast -vvvv
///         Requiere en env: POOL_ADDRESS y ASP_ADDRESS (addresses del deploy) y
///         PRIVATE_KEY (owner del ASP / deployer). El hasher se lee de
///         pool.hasher(); no se pide por env.
///
/// @dev IMPORTANTE: el deployer debe tener al menos 3×denominación de ETH de
///      faucet (los 3 depósitos de demo salen de su balance). En la demo el
///      association set == árbol de estado (simplificación ya documentada en
///      frontend/dapp/src/lib/zk.ts): por eso publicamos getLastRoot() tras los
///      depósitos. Mismo parseo de PRIVATE_KEY que DeployPool (acepta con/sin 0x).
contract SeedDemo is Script {
    /// @dev Notas de demo DETERMINISTAS: (nullifier, secret). Bigints chicos,
    ///      dentro del campo BN254. Son PÚBLICAS a propósito (van al README).
    uint256[3] internal NULLIFIERS = [uint256(1), uint256(2), uint256(3)];
    uint256[3] internal SECRETS = [uint256(11), uint256(22), uint256(33)];

    function run() external {
        // Acepta PRIVATE_KEY con o sin prefijo "0x" (igual que DeployPool).
        string memory pkStr = vm.envString("PRIVATE_KEY");
        if (bytes(pkStr).length == 64) {
            pkStr = string.concat("0x", pkStr);
        }
        uint256 pk = vm.parseUint(pkStr);

        PrivacyPool pool = PrivacyPool(vm.envAddress("POOL_ADDRESS"));
        ASP asp = ASP(vm.envAddress("ASP_ADDRESS"));
        IHasher hasher = pool.hasher();
        uint256 denomination = pool.denomination();

        vm.startBroadcast(pk);

        console.log("Sembrando pool de demo:", address(pool));
        console.log("  denominacion (wei):  ", denomination);
        console.log("  se requieren 3x denominacion de faucet en el deployer.");

        // 3 depósitos de demo con commitment = Poseidon(nullifier, secret).
        for (uint256 i = 0; i < 3; i++) {
            uint256 commitment = hasher.poseidon([NULLIFIERS[i], SECRETS[i]]);
            pool.deposit{value: denomination}(commitment);

            console.log("Nota de demo", i + 1);
            console.log("  nullifier: ", NULLIFIERS[i]);
            console.log("  secret:    ", SECRETS[i]);
            console.log("  commitment:", commitment);
        }

        // El association set de la demo es el árbol de estado completo: publicamos
        // la raíz vigente para que las 3 notas puedan retirar.
        uint256 root = pool.getLastRoot();
        asp.publishAssociationRoot(root);
        console.log("Association root publicada:", root);

        vm.stopBroadcast();

        console.log("Listo. Pega las 3 notas (nullifier, secret) en el README:");
        console.log("un visitante puede retirarlas desde la dApp (demo self-service).");
    }
}
