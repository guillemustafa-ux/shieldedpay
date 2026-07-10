// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IASPRegistry} from "./interfaces/IASPRegistry.sol";

/// @title ASPRegistry — registry on-chain multi-ASP (Layer 3 + stub de Layer 5)
/// @notice Reemplazo DESCENTRALIZADO del `ASP.sol` single-owner. En vez de un
///         único owner que decide qué raíces de asociación son válidas, acá
///         conviven MUCHOS Association Set Providers: cada uno se registra con
///         un stake, publica sus propias association roots, y el pool
///         (PrivacyPoolMultiASP) acepta un retiro contra el ASP que el usuario
///         elija. El circuito ZK NO cambia: la descentralización vive
///         enteramente en QUÉ roots honra el pool (una consulta al registry),
///         no en la criptografía. Ver docs/DECENTRALIZED-ASP.md.
///
///         Qué capas del diseño implementa este slice:
///           - Layer 3 (On-chain: registry + publicación de roots multi-ASP):
///             IMPLEMENTADO. register() con stake, publishRoot() con historial
///             circular por-ASP, isActive()/isKnownRoot() para el pool.
///           - Layer 5 (Accountability: staking + slashing): STUB. El stake se
///             retiene; slash() existe pero lo dispara el owner del registry
///             (governance placeholder), no un fraud proof.
///
/// @dev LIMITACIONES CONSCIENTES (documentadas, no ocultas) — todo esto es
///      trabajo futuro descripto en DECENTRALIZED-ASP.md:
///        1. SLASHING POR GOVERNANCE (stub). En el diseño real (Layer 5) el
///           slashing se dispara por un FRAUD PROOF verificable
///           (data-withholding: el `dataHash` no está disponible; o
///           rule-violation: el set publicado no matchea la recomputación
///           determinística de Layer 1). Acá slash() es discrecional del owner
///           del registry: el placeholder mínimo del slice, NO el mecanismo
///           final.
///        2. DATA AVAILABILITY NO VALIDADA (Layer 2). Guardamos el `dataHash`
///           (commitment content-addressed del set publicado) junto a cada root,
///           pero NO verificamos que el contenido esté disponible ni que matchee.
///           Esa validación (y el slashing por withholding) es futura.
///        3. minAssociationSetSize NO CHEQUEADO. Un ASP degenerado que publique
///           un set de tamaño 1 desanonimiza al usuario (ver threat model,
///           sección 8). Rechazar sets degenerados en el registry es futuro.
contract ASPRegistry is IASPRegistry, Ownable {
    /// @notice Cantidad de association roots recientes que recordamos por ASP
    ///         (ventana circular por-ASP; mismo patrón conceptual que
    ///         MerkleTreeWithHistory, pero una historia independiente por aspId).
    uint32 public constant ROOT_HISTORY_SIZE = 30;

    /// @notice Stake mínimo (wei) para registrar un ASP. Inmutable, fijado por
    ///         constructor. En el stub el stake sólo se retiene (no hay recompensa
    ///         ni retiro); su rol es servir de garantía slasheable en Layer 5.
    uint256 public immutable MIN_STAKE;

    /// @notice Datos de cada ASP registrado. `owner` == address(0) => no existe.
    /// @dev El historial de roots vive aparte (`aspRoots`) porque un struct no
    ///      puede contener el mapping de la ventana circular.
    struct ASPInfo {
        address owner; // quién administra este ASP (publica sus roots)
        bytes32 policyHash; // hash de la política (propagación + attesters + disputa)
        string metadataURI; // URI con la política legible / metadata del ASP
        uint256 stake; // stake depositado al registrarse (retenido)
        bool slashed; // marcado por governance (stub de Layer 5)
        uint256 latestRoot; // última root publicada (conveniencia off-chain)
        bytes32 latestDataHash; // dataHash de la última root (commitment DA, Layer 2)
        uint32 currentRootIndex; // índice vigente en la ventana circular de este ASP
    }

    /// @notice aspId => datos del ASP.
    mapping(uint256 => ASPInfo) public asps;

    /// @notice aspId => (índice circular => association root). Historial reciente
    ///         por-ASP; el valor 0 marca un slot aún no escrito.
    mapping(uint256 => mapping(uint32 => uint256)) internal aspRoots;

    /// @notice Próximo aspId a asignar. Los ids son incrementales desde 1 (el 0
    ///         queda reservado como "no existe").
    uint256 public nextAspId = 1;

    /// @param aspId Id asignado al ASP recién registrado.
    /// @param owner Dirección que administra el ASP.
    /// @param policyHash Hash de la política declarada.
    event ASPRegistered(uint256 indexed aspId, address indexed owner, bytes32 policyHash);

    /// @param aspId ASP que publicó la root.
    /// @param root Association root publicada.
    /// @param dataHash Commitment de data-availability del set (Layer 2, no validado aún).
    event RootPublished(uint256 indexed aspId, uint256 indexed root, bytes32 dataHash);

    /// @param aspId ASP marcado como slashed por governance (stub).
    event ASPSlashed(uint256 indexed aspId);

    /// @param _minStake Stake mínimo (wei) exigido para registrar un ASP.
    /// @param _governance Owner del registry: dispara slash() (placeholder de
    ///        gobernanza; en el diseño real sería un fraud-proof adjudicator).
    constructor(uint256 _minStake, address _governance) Ownable(_governance) {
        MIN_STAKE = _minStake;
    }

    /// @notice Registra un nuevo ASP depositando al menos MIN_STAKE.
    /// @dev El stake queda retenido en el contrato (garantía slasheable). El
    ///      aspId es incremental desde 1.
    /// @param policyHash Hash de la política del ASP (propagación + attesters + disputa).
    /// @param metadataURI URI con la política legible / metadata.
    /// @return aspId Id asignado al ASP.
    function register(bytes32 policyHash, string calldata metadataURI)
        external
        payable
        returns (uint256 aspId)
    {
        require(msg.value >= MIN_STAKE, "stake insuficiente");

        aspId = nextAspId++;
        ASPInfo storage info = asps[aspId];
        info.owner = msg.sender;
        info.policyHash = policyHash;
        info.metadataURI = metadataURI;
        info.stake = msg.value;
        // slashed = false, latestRoot = 0, currentRootIndex = 0 por default.

        emit ASPRegistered(aspId, msg.sender, policyHash);
    }

    /// @notice Publica una nueva association root para `aspId`.
    /// @dev Sólo el owner del ASP. Revierte si el ASP no existe o está slashed.
    ///      Guarda la root en la ventana circular de ESE ASP y actualiza
    ///      `latestRoot`/`latestDataHash`. El `dataHash` (commitment DA de Layer 2)
    ///      se ALMACENA pero NO se valida disponibilidad en este slice.
    /// @param aspId ASP que publica.
    /// @param root Association root construida off-chain.
    /// @param dataHash Commitment content-addressed del set (IPFS/Arweave/blob).
    function publishRoot(uint256 aspId, uint256 root, bytes32 dataHash) external {
        ASPInfo storage info = asps[aspId];
        require(info.owner != address(0), "ASP inexistente");
        require(!info.slashed, "ASP slashed");
        require(msg.sender == info.owner, "solo el owner del ASP");

        uint32 newRootIndex = (info.currentRootIndex + 1) % ROOT_HISTORY_SIZE;
        info.currentRootIndex = newRootIndex;
        aspRoots[aspId][newRootIndex] = root;
        info.latestRoot = root;
        info.latestDataHash = dataHash;

        emit RootPublished(aspId, root, dataHash);
    }

    /// @notice Marca un ASP como slashed (STUB de governance).
    /// @dev Sólo el owner del REGISTRY (governance placeholder). Un ASP slashed
    ///      deja de ser `isActive`, así que sus roots dejan de servir para
    ///      retirar. El stake queda retenido en el contrato. En el diseño real
    ///      (Layer 5, ver DECENTRALIZED-ASP.md) esto lo dispara un FRAUD PROOF
    ///      verificable (data-withholding / rule-violation), no la discreción del
    ///      governance: este método es el placeholder mínimo del slice.
    /// @param aspId ASP a slashear.
    function slash(uint256 aspId) external onlyOwner {
        ASPInfo storage info = asps[aspId];
        require(info.owner != address(0), "ASP inexistente");
        info.slashed = true;
        emit ASPSlashed(aspId);
    }

    /// @inheritdoc IASPRegistry
    /// @dev Activo == existe (owner != 0) y no slashed.
    function isActive(uint256 aspId) external view returns (bool) {
        ASPInfo storage info = asps[aspId];
        return info.owner != address(0) && !info.slashed;
    }

    /// @inheritdoc IASPRegistry
    /// @dev Recorre la ventana circular de ESE aspId hacia atrás desde la root
    ///      vigente; ignora slots en 0 (aún no escritos). No chequea slashed: el
    ///      pool combina isActive() && isKnownRoot() (ver PrivacyPoolMultiASP).
    function isKnownRoot(uint256 aspId, uint256 root) external view returns (bool) {
        if (root == 0) return false;
        ASPInfo storage info = asps[aspId];
        if (info.owner == address(0)) return false;

        uint32 current = info.currentRootIndex;
        uint32 i = current;
        do {
            if (root == aspRoots[aspId][i]) return true;
            if (i == 0) {
                i = ROOT_HISTORY_SIZE;
            }
            i--;
        } while (i != current);
        return false;
    }
}
