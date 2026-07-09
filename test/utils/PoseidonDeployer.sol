// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {IHasher} from "../../src/interfaces/IHasher.sol";

/// @title PoseidonDeployer — deploya el hasher Poseidon(2) desde bytecode
/// @notice El hasher Poseidon(2) no se puede escribir a mano en Solidity de
///         forma que matchee circomlibjs bit-a-bit: usamos el bytecode que
///         genera circomlibjs (`poseidonContract.createCode(2)`), guardado en
///         test/fixtures/poseidonBytecode.txt por circuits/scripts/genPoseidon.js,
///         y lo deployamos con `create` en assembly. Es el mismo patrón que
///         usan Tornado Cash y Privacy Pools.
/// @dev Función `internal` que recibe el `Vm` del caller (Test o Script), así el
///      mismo helper sirve tanto en los tests como en el script de deploy.
library PoseidonDeployer {
    /// @notice Lee el bytecode del fixture y deploya el hasher.
    /// @param vm Cheatcodes de Foundry (Test/Script exponen `vm`).
    /// @return hasher Instancia del hasher Poseidon(2) deployado.
    function deploy(Vm vm) internal returns (IHasher hasher) {
        string memory hexStr = vm.readFile("test/fixtures/poseidonBytecode.txt");
        bytes memory bytecode = vm.parseBytes(hexStr);

        address addr;
        assembly {
            addr := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        require(addr != address(0), "deploy del hasher Poseidon fallo");
        return IHasher(addr);
    }
}
