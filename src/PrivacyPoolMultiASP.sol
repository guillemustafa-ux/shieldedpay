// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {MerkleTreeWithHistory} from "./MerkleTreeWithHistory.sol";
import {IVerifier} from "./interfaces/IVerifier.sol";
import {IHasher} from "./interfaces/IHasher.sol";
import {IASPRegistry} from "./interfaces/IASPRegistry.sol";

/// @title PrivacyPoolMultiASP — pool de depósitos anónimos contra un registry multi-ASP
/// @notice Variante de PrivacyPool que reemplaza el ASP single-owner por un
///         registry descentralizado (IASPRegistry, ver src/ASPRegistry.sol y
///         docs/DECENTRALIZED-ASP.md, Layer 3). El depósito es idéntico; lo que
///         cambia es el retiro: el usuario ELIGE contra qué ASP validar su
///         association root (parámetro `aspId`), y el pool exige que ese ASP
///         siga activo (registrado y no slashed) y que la root esté en su
///         historial reciente.
///
///         IMPORTANTE — el circuito ZK y la prueba NO cambian respecto de
///         PrivacyPool. `aspId` es un SELECTOR on-chain (contra qué ASP validar
///         la associationRoot), NO una señal pública del circuito: las 6 señales
///         públicas y su orden son idénticas
///         [root, associationRoot, nullifierHash, recipient, relayer, fee]. Por
///         eso la misma prueba Groth16 que verifica contra PrivacyPool verifica
///         acá: el cambio a registry no toca la criptografía.
///
///         Flujo:
///           1. deposit(commitment): igual que PrivacyPool.
///           2. (off-chain) un ASP registrado incluye tu commitment en su set
///              limpio y publica la nueva associationRoot vía ASPRegistry.
///           3. withdraw(..., aspId): con una prueba ZK demostrás pertenencia al
///              pool y al set limpio; el pool valida la associationRoot contra el
///              ASP `aspId` que elegiste.
contract PrivacyPoolMultiASP is MerkleTreeWithHistory, ReentrancyGuard {
    /// @notice Verificador Groth16 del circuito withdraw.
    IVerifier public immutable verifier;

    /// @notice Registry multi-ASP consultado al retirar (reemplaza al IASP único).
    IASPRegistry public immutable registry;

    /// @notice Monto fijo (en wei) de cada depósito/retiro. La denominación fija
    ///         es lo que hace indistinguibles los depósitos entre sí.
    uint256 public immutable denomination;

    /// @notice Commitments ya insertados (anti-duplicado en depósito).
    mapping(uint256 => bool) public commitments;

    /// @notice nullifierHashes ya gastados (anti double-spend en retiro).
    mapping(uint256 => bool) public nullifierHashes;

    /// @param commitment Commitment insertado.
    /// @param leafIndex Índice de la hoja en el árbol.
    /// @param timestamp Momento del depósito.
    event Deposit(uint256 indexed commitment, uint32 leafIndex, uint256 timestamp);

    /// @param to Destinatario de los fondos.
    /// @param nullifierHash Nullifier marcado como gastado en este retiro.
    /// @param relayer Relayer que ejecutó (0 si retiró el propio usuario).
    /// @param fee Fee pagado al relayer (en wei).
    event Withdrawal(address indexed to, uint256 indexed nullifierHash, address indexed relayer, uint256 fee);

    /// @param _verifier Verificador Groth16 del circuito withdraw.
    /// @param _hasher Hasher Poseidon(2) on-chain.
    /// @param _registry Registry multi-ASP.
    /// @param _denomination Monto fijo por depósito/retiro (wei).
    /// @param _levels Altura del árbol (20).
    constructor(
        IVerifier _verifier,
        IHasher _hasher,
        IASPRegistry _registry,
        uint256 _denomination,
        uint32 _levels
    ) MerkleTreeWithHistory(_levels, _hasher) {
        require(_denomination > 0, "denominacion debe ser > 0");
        verifier = _verifier;
        registry = _registry;
        denomination = _denomination;
    }

    /// @notice Deposita `denomination` ETH publicando `commitment`.
    /// @dev El commitment debe ser único (un mismo recibo no puede insertarse
    ///      dos veces) y el monto debe ser EXACTAMENTE la denominación.
    /// @param commitment Poseidon(nullifier, secret), calculado off-chain.
    function deposit(uint256 commitment) external payable nonReentrant {
        require(msg.value == denomination, "el monto debe ser la denominacion exacta");
        require(!commitments[commitment], "commitment ya depositado");
        require(commitment < FIELD_SIZE, "commitment fuera del campo");

        uint32 index = _insert(commitment);
        commitments[commitment] = true;

        emit Deposit(commitment, index, block.timestamp);
    }

    /// @notice Retira `denomination - fee` a `recipient` (y `fee` a `relayer`)
    ///         probando pertenencia al pool y al set limpio del ASP elegido, sin
    ///         revelar cuál depósito se retira.
    /// @dev El orden de las señales públicas del array `pub` DEBE ser el del
    ///      circuito (root, associationRoot, nullifierHash, recipient, relayer,
    ///      fee). `aspId` NO entra al array público: es un selector on-chain de
    ///      contra qué ASP validar la associationRoot, no una señal ZK. La
    ///      validación de asociación pasa de `asp.isKnownAssociationRoot(...)` a
    ///      `registry.isActive(aspId) && registry.isKnownRoot(aspId, associationRoot)`.
    /// @param pA Punto G1 (a) de la prueba Groth16.
    /// @param pB Punto G2 (b) de la prueba.
    /// @param pC Punto G1 (c) de la prueba.
    /// @param root Raíz de estado contra la que se probó membresía.
    /// @param associationRoot Raíz de asociación (set limpio) del ASP elegido.
    /// @param nullifierHash Poseidon(nullifier), se marca como gastado.
    /// @param recipient Destino de los fondos.
    /// @param relayer Relayer (0 si retira el propio usuario).
    /// @param fee Fee para el relayer (wei), <= denomination.
    /// @param aspId ASP del registry contra el que se valida la associationRoot.
    function withdraw(
        uint[2] calldata pA,
        uint[2][2] calldata pB,
        uint[2] calldata pC,
        uint256 root,
        uint256 associationRoot,
        uint256 nullifierHash,
        address payable recipient,
        address payable relayer,
        uint256 fee,
        uint256 aspId
    ) external nonReentrant {
        require(!nullifierHashes[nullifierHash], "nota ya gastada");
        require(fee <= denomination, "el fee no puede superar la denominacion");
        // Sin relayer, un fee > 0 quedaría atrapado en el contrato (no se reenvía
        // a nadie): footgun que rompe el invariante de balance. Este guard lo cierra.
        require(relayer != address(0) || fee == 0, "fee > 0 requiere un relayer");
        require(isKnownRoot(root), "raiz de estado desconocida");
        require(
            registry.isActive(aspId) && registry.isKnownRoot(aspId, associationRoot),
            "ASP inactivo o root desconocida"
        );

        uint[6] memory pub = [
            root,
            associationRoot,
            nullifierHash,
            uint256(uint160(address(recipient))),
            uint256(uint160(address(relayer))),
            fee
        ];
        require(verifier.verifyProof(pA, pB, pC, pub), "prueba invalida");

        // Efecto ANTES de la interacción (checks-effects-interactions + guard).
        nullifierHashes[nullifierHash] = true;

        uint256 amount = denomination - fee;
        (bool okRecipient, ) = recipient.call{value: amount}("");
        require(okRecipient, "transferencia al recipient fallo");

        if (fee > 0 && relayer != address(0)) {
            (bool okRelayer, ) = relayer.call{value: fee}("");
            require(okRelayer, "transferencia al relayer fallo");
        }

        emit Withdrawal(recipient, nullifierHash, relayer, fee);
    }
}
