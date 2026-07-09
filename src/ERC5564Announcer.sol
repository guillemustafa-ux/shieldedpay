// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IERC5564Announcer — interfaz del EIP-5564 (Stealth Addresses)
/// @notice Contrato "anunciador" canónico: el pagador lo llama para que quede
///         registrado on-chain que le pagó a una stealth address, junto con
///         la clave efímera que el receptor necesita para escanear y derivar
///         su clave privada correspondiente.
interface IERC5564Announcer {
    /// @dev Ver especificación completa en https://eips.ethereum.org/EIPS/eip-5564
    /// @param schemeId Identificador del esquema de derivación stealth usado
    ///        (1 = secp256k1 con vista/gasto separados, el único definido hoy).
    /// @param stealthAddress Dirección stealth generada por el pagador, a la
    ///        que efectivamente se mandaron los fondos/tokens.
    /// @param caller address que ejecuta el announce (normalmente el pagador,
    ///        pero puede ser un relayer en nombre de este).
    /// @param ephemeralPubKey Clave pública efímera (comprimida) generada por
    ///        el pagador; el receptor la usa junto a su viewing key para
    ///        recomputar el secreto compartido.
    /// @param metadata Bytes libres: por convención el primer byte es el
    ///        "view tag" (un byte del hash del secreto compartido) que le
    ///        permite al receptor descartar rápido anuncios que no son suyos
    ///        sin tener que hacer la derivación completa de ECDH.
    event Announcement(
        uint256 indexed schemeId,
        address indexed stealthAddress,
        address indexed caller,
        bytes ephemeralPubKey,
        bytes metadata
    );

    /// @notice Anuncia un pago a una stealth address. Cualquiera puede llamarlo:
    ///         el contrato es stateless, solo emite el evento `Announcement`.
    /// @param schemeId Esquema de derivación usado para generar `stealthAddress`.
    /// @param stealthAddress Dirección stealth destino del pago.
    /// @param ephemeralPubKey Clave pública efímera del pagador (formato según scheme).
    /// @param metadata Metadata libre (por convención: view tag en el primer byte).
    function announce(
        uint256 schemeId,
        address stealthAddress,
        bytes memory ephemeralPubKey,
        bytes memory metadata
    ) external;
}

/// @title ERC5564Announcer — implementación canónica y stateless del EIP-5564
/// @notice No guarda estado ni valida nada sobre el esquema: es un simple
///         "megáfono" on-chain. Los receptores escanean estos eventos off-chain
///         (o vía indexer) para descubrir pagos dirigidos a ellos.
contract ERC5564Announcer is IERC5564Announcer {
    /// @inheritdoc IERC5564Announcer
    function announce(
        uint256 schemeId,
        address stealthAddress,
        bytes memory ephemeralPubKey,
        bytes memory metadata
    ) external {
        emit Announcement(schemeId, stealthAddress, msg.sender, ephemeralPubKey, metadata);
    }
}
