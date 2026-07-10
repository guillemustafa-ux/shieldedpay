// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IFlaggedRegistry — interfaz que el ASPRegistry consume del registro de marcados
/// @notice El ASPRegistry sólo necesita consultar UNA cosa del FlaggedRegistry:
///         si un commitment está marcado como sucio (la salida del taint analysis
///         de Layer 1, colapsada a un registro on-chain que un attester mantiene
///         off-chain). Con eso el fraud proof de permisividad (challengeInclusion)
///         puede probar que un ASP incluyó un commitment marcado en su set "limpio".
/// @dev El registro concreto (FlaggedRegistry) expone además flag/unflag onlyOwner.
///      Ver src/FlaggedRegistry.sol y docs/DECENTRALIZED-ASP.md (Layer 1 / Layer 4).
interface IFlaggedRegistry {
    /// @return true si `commitment` fue marcado como sucio por el attester.
    function isFlagged(uint256 commitment) external view returns (bool);
}
