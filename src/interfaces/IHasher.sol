// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IHasher — interfaz del hasher Poseidon(2) on-chain
/// @notice El árbol de Merkle del pool hashea cada par (izq, der) con este
///         contrato. El bytecode del hasher se genera con circomlibjs
///         (`poseidonContract.createCode(2)`) y se deploya desde ese bytecode,
///         de modo que produce EXACTAMENTE el mismo hash que
///         circomlibjs.buildPoseidon() (el harness JS) y que el circuito
///         `Poseidon(2)`. Si el hasher no matcheara circomlibjs bit-a-bit, las
///         raíces on-chain no coincidirían con las que prueba el circuito y
///         ninguna verificación cerraría.
/// @dev El contrato generado expone dos overloads de `poseidon` (uno con
///      bytes32[2] y otro con uint256[2]); usamos el de uint256[2].
interface IHasher {
    function poseidon(uint256[2] calldata input) external pure returns (uint256);
}
