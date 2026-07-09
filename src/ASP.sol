// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IASP} from "./interfaces/IASP.sol";

/// @title ASP — Association Set Provider (versión owner-controlled, para portfolio)
/// @notice En el diseño de Privacy Pools (Buterin/Illum/Nadler/Schär 2023) el
///         ASP mantiene OFF-CHAIN un árbol de asociación: el subconjunto de
///         commitments del pool que declaró "limpios" (por ejemplo, tras
///         screenear el origen de cada depósito). Cada vez que actualiza ese
///         set, publica su nueva raíz on-chain. El pool exige, al retirar, que
///         la `associationRoot` de la prueba ZK sea una raíz que este ASP haya
///         publicado — así un depósito que quedó FUERA del set limpio no puede
///         retirar, aunque sea un depósito real del pool.
///
/// @dev LIMITACIÓN CONSCIENTE (documentada, no oculta): acá el ASP es un simple
///      `Ownable`. Un único owner decide qué raíces son válidas. En producción
///      esto sería un servicio de screening (tipo 0xbow / Chainalysis-like) o
///      una gobernanza descentralizada; NO prometemos descentralización en esta
///      pieza. El árbol de asociación se construye off-chain (ver
///      circuits/test/merkleTree.js); on-chain sólo registramos sus raíces.
contract ASP is IASP, Ownable {
    /// @notice Raíces de asociación publicadas por el owner (válidas para retirar).
    mapping(uint256 => bool) public isKnownAssociationRoot;

    /// @notice Última raíz publicada (conveniencia para off-chain / frontends).
    uint256 public latestAssociationRoot;

    /// @param root Raíz del árbol de asociación recién publicada.
    /// @param timestamp Momento de la publicación (block.timestamp).
    event AssociationRootPublished(uint256 indexed root, uint256 timestamp);

    /// @param initialOwner Dirección que administra el ASP (publica raíces).
    constructor(address initialOwner) Ownable(initialOwner) {}

    /// @notice Publica una nueva raíz de asociación como válida.
    /// @dev Sólo el owner. Idempotente: republicar una raíz ya conocida es
    ///      inocuo (vuelve a marcarla true y actualiza `latest`).
    /// @param root Raíz del árbol de asociación construido off-chain.
    function publishAssociationRoot(uint256 root) external onlyOwner {
        isKnownAssociationRoot[root] = true;
        latestAssociationRoot = root;
        emit AssociationRootPublished(root, block.timestamp);
    }
}
