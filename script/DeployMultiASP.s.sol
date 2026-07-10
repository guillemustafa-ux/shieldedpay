// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {PrivacyPoolMultiASP} from "../src/PrivacyPoolMultiASP.sol";
import {ASPRegistry} from "../src/ASPRegistry.sol";
import {FlaggedRegistry} from "../src/FlaggedRegistry.sol";
import {IVerifier} from "../src/interfaces/IVerifier.sol";
import {IHasher} from "../src/interfaces/IHasher.sol";
import {IASPRegistry} from "../src/interfaces/IASPRegistry.sol";
import {IFlaggedRegistry} from "../src/interfaces/IFlaggedRegistry.sol";
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
        returns (
            IHasher hasher,
            Groth16Verifier verifier,
            FlaggedRegistry flaggedRegistry,
            ASPRegistry registry,
            PrivacyPoolMultiASP pool
        )
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

        // Reutiliza hasher/verifier YA deployados si se pasan por env (HASHER_ADDRESS,
        // VERIFIER_ADDRESS): el Poseidon(2) y el verifier del circuito son bytecode
        // fijo e idéntico al de un deploy previo, así que redeployarlos sólo quema gas.
        // Si no se pasan (address(0)), los deploya fresh como antes.
        address hasherAddr = vm.envOr("HASHER_ADDRESS", address(0));
        address verifierAddr = vm.envOr("VERIFIER_ADDRESS", address(0));

        vm.startBroadcast(pk);

        hasher = hasherAddr == address(0) ? PoseidonDeployer.deploy(vm) : IHasher(hasherAddr);
        verifier = verifierAddr == address(0) ? new Groth16Verifier() : Groth16Verifier(verifierAddr);
        // FlaggedRegistry: el deployer queda como attester (stub de Layer 4; en el
        // diseño real son attestations con disputas, ver su NatSpec). Alimenta el
        // fraud proof de permisividad (challengeInclusion).
        flaggedRegistry = new FlaggedRegistry(deployer);
        // El deployer queda como governance del registry (sólo slash de emergencia;
        // el slashing primario es el fraud proof, que no requiere governance). El
        // registry necesita el MISMO hasher que el pool para recomputar Merkle
        // roots dentro de los fraud proofs (challengeIntegrity) y el FlaggedRegistry
        // para el fraud proof de permisividad (challengeInclusion).
        registry = new ASPRegistry(minStake, deployer, hasher, IFlaggedRegistry(address(flaggedRegistry)));
        pool = new PrivacyPoolMultiASP(
            IVerifier(address(verifier)), hasher, IASPRegistry(address(registry)), denomination, LEVELS
        );

        vm.stopBroadcast();

        console.log("Hasher Poseidon(2) desplegado en:", address(hasher));
        console.log("Groth16Verifier desplegado en:   ", address(verifier));
        console.log("FlaggedRegistry desplegado en:   ", address(flaggedRegistry));
        console.log("  attester (owner):              ", deployer);
        console.log("ASPRegistry desplegado en:       ", address(registry));
        console.log("  governance (owner):            ", deployer);
        console.log("  stake minimo (wei):            ", minStake);
        console.log("PrivacyPoolMultiASP desplegado en:", address(pool));
        console.log("  denominacion (wei):            ", denomination);
        console.log("Pega estas addresses en el README y en el frontend/dapp.");
    }
}
