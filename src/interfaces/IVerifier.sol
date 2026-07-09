// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IVerifier — interfaz del verificador Groth16 del circuito withdraw
/// @notice El contrato `Groth16Verifier` en src/verifiers/WithdrawVerifier.sol
///         (generado por snarkjs a partir de circuits/withdraw.circom) expone
///         exactamente esta firma. El pool la usa para no depender de la
///         implementación concreta: cualquier verifier que respete esta
///         interfaz (y el mismo circuito) sirve.
/// @dev IMPORTANTE — el ORDEN de las 6 señales públicas lo fija el circuito:
///        component main {public [root, associationRoot, nullifierHash,
///                                recipient, relayer, fee]}
///      => _pubSignals[0]=root, [1]=associationRoot, [2]=nullifierHash,
///         [3]=recipient (address como uint256), [4]=relayer (idem), [5]=fee.
///      Armar el array en otro orden hace fallar la verificación aunque la
///      prueba sea legítima.
interface IVerifier {
    /// @param _pA Punto G1 de la prueba (a).
    /// @param _pB Punto G2 de la prueba (b).
    /// @param _pC Punto G1 de la prueba (c).
    /// @param _pubSignals Las 6 señales públicas, en el orden del circuito.
    /// @return true si la prueba es válida para esas señales públicas.
    function verifyProof(
        uint[2] calldata _pA,
        uint[2][2] calldata _pB,
        uint[2] calldata _pC,
        uint[6] calldata _pubSignals
    ) external view returns (bool);
}
