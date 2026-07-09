// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

/// @title ERC6538Registry — registro de stealth meta-addresses (EIP-6538)
/// @notice Cada cuenta publica acá su "meta-address" (claves públicas de gasto
///         y de vista, serializadas) por esquema de derivación stealth. Un
///         pagador lee esto para poder generar una stealth address dirigida
///         a esa cuenta (ver ERC-5564). El contrato solo guarda bytes: no le
///         importa el formato interno de la meta-address, eso lo define cada
///         `schemeId`.
contract ERC6538Registry is EIP712 {
    /// @notice Stealth meta-address publicada por cada registrant, por esquema.
    mapping(address registrant => mapping(uint256 schemeId => bytes)) public stealthMetaAddressOf;

    /// @notice Nonce incremental por registrant, usado para invalidar firmas
    ///         de `registerKeysOnBehalf` ya consumidas (protección anti-replay).
    mapping(address registrant => uint256) public nonceOf;

    /// @dev keccak256("RegisterKeysOnBehalf(address registrant,uint256 schemeId,uint256 nonce,bytes stealthMetaAddress)")
    bytes32 private constant REGISTER_TYPEHASH =
        keccak256("RegisterKeysOnBehalf(address registrant,uint256 schemeId,uint256 nonce,bytes stealthMetaAddress)");

    /// @notice Se emite cada vez que se fija (o sobrescribe) una stealth
    ///         meta-address, tanto por `registerKeys` como por
    ///         `registerKeysOnBehalf`.
    event StealthMetaAddressSet(address indexed registrant, uint256 indexed schemeId, bytes stealthMetaAddress);

    /// @notice La firma provista para `registerKeysOnBehalf` no valida contra
    ///         `registrant` para el digest EIP-712 esperado (que incluye el
    ///         `schemeId`, el nonce ACTUAL de `registrant` y la meta-address).
    ///         También se revierte con este error si el nonce usado para
    ///         firmar quedó desactualizado (ej. una firma vieja tras un
    ///         registro previo, o una firmada con un nonce futuro).
    error InvalidSignature();

    constructor() EIP712("ERC6538Registry", "1.0") {}

    /// @notice El caller registra su propia stealth meta-address para `schemeId`.
    /// @dev Sobrescribe cualquier valor previo para ese (registrant, schemeId).
    ///      No requiere firma: `msg.sender` es el registrant.
    function registerKeys(uint256 schemeId, bytes memory stealthMetaAddress) external {
        _setStealthMetaAddress(msg.sender, schemeId, stealthMetaAddress);
    }

    /// @notice Registra la stealth meta-address de `registrant` en su nombre,
    ///         validando una firma EIP-712 sobre (registrant, schemeId, nonce
    ///         actual, stealthMetaAddress). Soporta firmas EOA (ECDSA) y de
    ///         smart contract wallets (ERC-1271) vía `SignatureChecker`.
    /// @dev El nonce se lee de `nonceOf[registrant]` (no es un parámetro): el
    ///      digest se arma con el valor vigente, y recién se incrementa si la
    ///      firma resulta válida. Así, una firma capturada y reenviada
    ///      (replay) deja de ser válida apenas se usó una vez, porque el
    ///      nonce vigente ya cambió.
    function registerKeysOnBehalf(
        address registrant,
        uint256 schemeId,
        bytes memory signature,
        bytes memory stealthMetaAddress
    ) external {
        uint256 nonce = nonceOf[registrant];
        bytes32 digest = _hashTypedDataV4(
            keccak256(abi.encode(REGISTER_TYPEHASH, registrant, schemeId, nonce, keccak256(stealthMetaAddress)))
        );

        if (!SignatureChecker.isValidSignatureNow(registrant, digest, signature)) {
            revert InvalidSignature();
        }

        nonceOf[registrant] = nonce + 1;
        _setStealthMetaAddress(registrant, schemeId, stealthMetaAddress);
    }

    function _setStealthMetaAddress(address registrant, uint256 schemeId, bytes memory stealthMetaAddress) internal {
        stealthMetaAddressOf[registrant][schemeId] = stealthMetaAddress;
        emit StealthMetaAddressSet(registrant, schemeId, stealthMetaAddress);
    }
}
