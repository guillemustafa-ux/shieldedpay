// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {PrivacyPool} from "../src/PrivacyPool.sol";
import {ASP} from "../src/ASP.sol";
import {IVerifier} from "../src/interfaces/IVerifier.sol";
import {IHasher} from "../src/interfaces/IHasher.sol";
import {IASP} from "../src/interfaces/IASP.sol";
import {Groth16Verifier} from "../src/verifiers/WithdrawVerifier.sol";
import {PoseidonDeployer} from "../test/utils/PoseidonDeployer.sol";

/// @title DeployPool — despliega el Privacy Pool completo (Fase B, D3)
/// @notice Deploya, en orden: hasher Poseidon(2) (desde el bytecode de
///         circomlibjs en test/fixtures/poseidonBytecode.txt), el verifier
///         Groth16 del circuito withdraw, el ASP (owner = deployer) y el
///         PrivacyPool que los ata. Corré:
///           forge script script/DeployPool.s.sol:DeployPool \
///             --rpc-url sepolia --broadcast --verify -vvvv
///         (sin --broadcast hace un dry-run local, sin gastar gas).
/// @dev Lee la PRIVATE_KEY de .env normalizando el prefijo "0x", igual que
///      DeployStealth. La denominación es configurable por env
///      (POOL_DENOMINATION, en wei); default 0.01 ETH. El hasher se deploya
///      desde bytecode (no se puede escribir a mano un Poseidon que matchee
///      circomlibjs); PoseidonDeployer necesita permiso de lectura de
///      test/fixtures (ya está en foundry.toml: fs_permissions).
contract DeployPool is Script {
    uint32 internal constant LEVELS = 20;

    function run()
        external
        returns (IHasher hasher, Groth16Verifier verifier, ASP asp, PrivacyPool pool)
    {
        // Acepta PRIVATE_KEY con o sin prefijo "0x".
        string memory pkStr = vm.envString("PRIVATE_KEY");
        if (bytes(pkStr).length == 64) {
            pkStr = string.concat("0x", pkStr);
        }
        uint256 pk = vm.parseUint(pkStr);
        address deployer = vm.addr(pk);

        // Denominación del pool (wei). Default 0.01 ETH.
        uint256 denomination = vm.envOr("POOL_DENOMINATION", uint256(0.01 ether));

        vm.startBroadcast(pk);

        hasher = PoseidonDeployer.deploy(vm);
        verifier = new Groth16Verifier();
        asp = new ASP(deployer);
        pool = new PrivacyPool(IVerifier(address(verifier)), hasher, IASP(address(asp)), denomination, LEVELS);

        vm.stopBroadcast();

        console.log("Hasher Poseidon(2) desplegado en:", address(hasher));
        console.log("Groth16Verifier desplegado en:   ", address(verifier));
        console.log("ASP desplegado en:               ", address(asp));
        console.log("PrivacyPool desplegado en:       ", address(pool));
        console.log("  denominacion (wei):            ", denomination);
        console.log("Pega estas addresses en el README y en el frontend/dapp.");
    }
}
