// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IASPRegistry — interfaz que el pool consume del registry multi-ASP
/// @notice Reemplazo descentralizado de IASP: en vez de preguntarle a UN solo
///         ASP owner-controlled si una raíz es válida, el pool consulta un
///         registry donde conviven muchos ASPs. El usuario elige contra QUÉ ASP
///         valida su retiro (parámetro `aspId` on-chain, no una señal ZK), y el
///         pool exige que ese ASP siga activo (registrado y no slashed) y que la
///         `associationRoot` esté en su historial reciente.
/// @dev El pool sólo necesita estas dos funciones; el registry concreto
///      (ASPRegistry) expone además registro con stake, publicación de roots y
///      slashing por governance. Ver src/ASPRegistry.sol y
///      docs/DECENTRALIZED-ASP.md (Layer 3).
interface IASPRegistry {
    /// @return true si el ASP existe y no fue slashed.
    function isActive(uint256 aspId) external view returns (bool);

    /// @return true si `root` está en el historial reciente de ESE `aspId` (root != 0).
    function isKnownRoot(uint256 aspId, uint256 root) external view returns (bool);
}
