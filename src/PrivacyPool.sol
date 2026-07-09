// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {MerkleTreeWithHistory} from "./MerkleTreeWithHistory.sol";
import {IVerifier} from "./interfaces/IVerifier.sol";
import {IHasher} from "./interfaces/IHasher.sol";
import {IASP} from "./interfaces/IASP.sol";

/// @title PrivacyPool — pool de depósitos anónimos con association set (Privacy Pools)
/// @notice Un mixer de denominación fija (estilo Tornado Cash) al que le
///         agregamos la capa de compliance de Privacy Pools: para retirar no
///         alcanza con probar que tu depósito está en el pool; además tenés que
///         probar que está en el "set limpio" que publicó el ASP. Así un
///         usuario honesto demuestra que sus fondos NO vienen de una fuente
///         marcada, sin revelar cuál de todos los depósitos es el suyo.
///
///         Flujo:
///           1. deposit(commitment): mandás `denomination` ETH y publicás tu
///              commitment = Poseidon(nullifier, secret). Queda como hoja del
///              árbol de estado. Guardás (nullifier, secret) en secreto.
///           2. (off-chain) el ASP incluye tu commitment en el set limpio y
///              publica la nueva associationRoot on-chain.
///           3. withdraw(...): con una prueba ZK demostrás que conocés un
///              (nullifier, secret) cuyo commitment está en `root` (estado) Y en
///              `associationRoot` (set limpio), sin revelar cuál. El contrato
///              paga a `recipient` (menos `fee` para el `relayer`) y marca el
///              nullifierHash como gastado.
contract PrivacyPool is MerkleTreeWithHistory, ReentrancyGuard {
    /// @notice Verificador Groth16 del circuito withdraw.
    IVerifier public immutable verifier;

    /// @notice Association Set Provider consultado al retirar.
    IASP public immutable asp;

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
    /// @param _asp Association Set Provider.
    /// @param _denomination Monto fijo por depósito/retiro (wei).
    /// @param _levels Altura del árbol (20).
    constructor(
        IVerifier _verifier,
        IHasher _hasher,
        IASP _asp,
        uint256 _denomination,
        uint32 _levels
    ) MerkleTreeWithHistory(_levels, _hasher) {
        require(_denomination > 0, "denominacion debe ser > 0");
        verifier = _verifier;
        asp = _asp;
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
    ///         probando pertenencia al pool y al set limpio, sin revelar cuál
    ///         depósito se retira.
    /// @dev El orden de las señales públicas del array `pub` DEBE ser el del
    ///      circuito (root, associationRoot, nullifierHash, recipient, relayer,
    ///      fee). recipient/relayer van como field elements
    ///      `uint256(uint160(addr))` porque así los recibió el circuito al
    ///      generar la prueba (ver withdraw.circom, binding xSquare).
    /// @param pA Punto G1 (a) de la prueba Groth16.
    /// @param pB Punto G2 (b) de la prueba.
    /// @param pC Punto G1 (c) de la prueba.
    /// @param root Raíz de estado contra la que se probó membresía.
    /// @param associationRoot Raíz de asociación (set limpio) del ASP.
    /// @param nullifierHash Poseidon(nullifier), se marca como gastado.
    /// @param recipient Destino de los fondos.
    /// @param relayer Relayer (0 si retira el propio usuario).
    /// @param fee Fee para el relayer (wei), <= denomination.
    function withdraw(
        uint[2] calldata pA,
        uint[2][2] calldata pB,
        uint[2] calldata pC,
        uint256 root,
        uint256 associationRoot,
        uint256 nullifierHash,
        address payable recipient,
        address payable relayer,
        uint256 fee
    ) external nonReentrant {
        require(!nullifierHashes[nullifierHash], "nota ya gastada");
        require(fee <= denomination, "el fee no puede superar la denominacion");
        require(isKnownRoot(root), "raiz de estado desconocida");
        require(asp.isKnownAssociationRoot(associationRoot), "association root no publicada por el ASP");

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
