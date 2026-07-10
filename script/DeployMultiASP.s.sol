// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {PrivacyPoolMultiASP} from "../src/PrivacyPoolMultiASP.sol";
import {ASPRegistry} from "../src/ASPRegistry.sol";
import {IVerifier} from "../src/interfaces/IVerifier.sol";
import {IHasher} from "../src/interfaces/IHasher.sol";
import {IASPRegistry} from "../src/interfaces/IASPRegistry.sol";
import {Groth16Verifier} from "../src/verifiers/WithdrawVerifier.sol";
import {PoseidonDeployer} from "../test/utils/PoseidonDeployer.sol";

/// @title DeployMultiASP — despliega el slice multi-ASP (Layer 3 + stub Layer 5)
/// @notice Deploya, en orden: hasher Poseidon(2) (desde el bytecode de
///         circomlibjs en test/fixtures/poseidonBytecode.txt), el verifier
///         Groth16 del circuito withdraw, el ASPRegistry (governance = deployer)
///         y el PrivacyPoolMultiASP que los ata. Corré:
///           forge script script/DeployMultiASP.s.sol:DeployMultiASP \
///             --rpc-url sepolia --broadcast --verify -vvvv
///         (sin --broadcast hace un dry-run local, sin gastar gas).
/// @dev Lee la PRIVATE_KEY de .env normalizando el prefijo "0x", igual que
///      DeployPool. Denominación configurable por env (POOL_DENOMINATION, wei;
///      default 0.01 ETH) y stake mínimo del registry por env (ASP_MIN_STAKE,
///      wei; default 0.01 ETH). El hasher se deploya desde bytecode;
///      PoseidonDeployer necesita permiso de lectura de test/fixtures (ya está
///      en foundry.toml: fs_permissions).
contract DeployMultiASP is Script {
    uint32 internal constant LEVELS = 20;

    function run()
        external
        returns (IHasher hasher, Groth16Verifier verifier, ASPRegistry registry, PrivacyPoolMultiASP pool)
    {
        // Acepta PRIVATE_KEY con o sin prefijo "0x".
        string memory pkStr = vm.envString("PRIVATE_KEY");
        if (bytes(pkStr).length == 64) {
            pkStr = string.concat("0x", pkStr);
        }
        uint256 pk = vm.parseUint(pkStr);
        address deployer = vm.addr(pk);

        // Denominación del pool y stake mínimo del registry (wei). Default 0.01 ETH.
        uint256 denomination = vm.envOr("POOL_DENOMINATION", uint256(0.01 ether));
        uint256 minStake = vm.envOr("ASP_MIN_STAKE", uint256(0.01 ether));

        vm.startBroadcast(pk);

        hasher = PoseidonDeployer.deploy(vm);
        verifier = new Groth16Verifier();
        // El deployer queda como governance del registry (sólo slash de emergencia;
        // el slashing primario es el fraud proof, que no requiere governance). El
        // registry necesita el MISMO hasher que el pool para recomputar Merkle
        // roots dentro de los fraud proofs (challengeIntegrity).
        registry = new ASPRegistry(minStake, deployer, hasher);
        pool = new PrivacyPoolMultiASP(
            IVerifier(address(verifier)), hasher, IASPRegistry(address(registry)), denomination, LEVELS
        );

        vm.stopBroadcast();

        console.log("Hasher Poseidon(2) desplegado en:", address(hasher));
        console.log("Groth16Verifier desplegado en:   ", address(verifier));
        console.log("ASPRegistry desplegado en:       ", address(registry));
        console.log("  governance (owner):            ", deployer);
        console.log("  stake minimo (wei):            ", minStake);
        console.log("PrivacyPoolMultiASP desplegado en:", address(pool));
        console.log("  denominacion (wei):            ", denomination);
        console.log("Pega estas addresses en el README y en el frontend/dapp.");
    }
}
