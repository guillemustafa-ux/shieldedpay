// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IASP — interfaz del Association Set Provider
/// @notice El pool sólo necesita poder preguntarle al ASP si una raíz de
///         asociación fue publicada (es decir, si el ASP la reconoce como un
///         "set limpio" válido). Cómo se administra ese ASP (owner simple,
///         multisig, servicio de screening descentralizado, etc.) es opaco
///         para el pool.
interface IASP {
    /// @return true si `root` fue publicada por el ASP como raíz de asociación válida.
    function isKnownAssociationRoot(uint256 root) external view returns (bool);
}
