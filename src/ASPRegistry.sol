// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IASPRegistry} from "./interfaces/IASPRegistry.sol";
import {IHasher} from "./interfaces/IHasher.sol";
import {PoseidonMerkleLib} from "./lib/PoseidonMerkleLib.sol";

/// @title ASPRegistry — registry on-chain multi-ASP (Layer 3 + Layer 5 con fraud proof)
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
///           - Layer 5 (Accountability: staking + slashing por FRAUD PROOF):
///             IMPLEMENTADO. El slashing primario ya NO es discrecional del
///             governance: lo dispara cualquiera que PRUEBE fraude on-chain.
///             Cuando un ASP publica (root, dataHash) se compromete a que `root`
///             es el Poseidon-Merkle root de un set cuyo `dataHash =
///             keccak256(abi.encodePacked(set))`. Un challenger prueba fraude
///             proveyendo ese set:
///               * challengeIntegrity: keccak(set) == dataHash comprometido PERO
///                 Merkle(set) recomputado on-chain != root publicada → el ASP
///                 mintió sobre su propia root → SLASH + recompensa al challenger.
///               * challengeDegenerate: keccak(set) == dataHash y set.length <
///                 MIN_SET_SIZE → el ASP publicó un set que desanonimiza usuarios
///                 → SLASH + recompensa.
///             Un ASP HONESTO (publicó root = Merkle(set) y dataHash = keccak(set))
///             NO es slasheable: cualquier challenge con el set correcto recomputa
///             la MISMA root y revierte "sin fraude". Un challenger que provee un
///             set con keccak != dataHash tampoco puede framear: revierte.
///
/// @dev LÍMITES HONESTOS (documentados, no ocultos) — trabajo futuro descripto en
///      DECENTRALIZED-ASP.md:
///        1. DATA-WITHHOLDING NO ES VERIFICABLE ON-CHAIN. El fraud proof cubre el
///           POSITIVO ("acá está el set y NO matchea / es degenerado"). El
///           NEGATIVO ("el ASP publicó un dataHash cuyo contenido no está
///           disponible en ningún lado") no se puede probar directamente en un
///           contrato: nadie puede demostrar la NO-existencia de un dato. Eso
///           requiere un protocolo challenge-response de revelación (el challenger
///           exige, el ASP debe revelar el preimage dentro de una ventana o es
///           slasheado). Fuera de alcance de este slice.
///        2. GAS DE SETS GRANDES. challenge* recomputa el Merkle root ENTERO del
///           set on-chain (O(n) hashes Poseidon). Es viable para sets chicos
///           (demo/tests) pero caro para sets de producción (miles de hojas). Un
///           fraud proof de producción probaría una INCONSISTENCIA PUNTUAL (una
///           rama del árbol que no cierra) en vez de recomputar todo — misma
///           idea, testigo sucinto. La recomputación completa es la versión
///           didáctica/correcta-por-construcción.
///        3. GOVERNANCE SLASH DE EMERGENCIA. Se conserva slash() onlyOwner como
///           backup (ver su NatSpec), pero el mecanismo PRIMARIO es el fraud proof.
contract ASPRegistry is IASPRegistry, Ownable, ReentrancyGuard {
    /// @notice Cantidad de association roots recientes que recordamos por ASP
    ///         (ventana circular por-ASP; mismo patrón conceptual que
    ///         MerkleTreeWithHistory, pero una historia independiente por aspId).
    uint32 public constant ROOT_HISTORY_SIZE = 30;

    /// @notice Tamaño mínimo del set de asociación. Un set de tamaño 1
    ///         desanonimiza por completo (la association root identifica UN único
    ///         commitment: no hay conjunto de anonimato). El valor 2 es el mínimo
    ///         estricto que provee algún anonimato; un ASP que publique un set más
    ///         chico es slasheable vía challengeDegenerate. (En producción se
    ///         subiría bastante más alto; 2 es el piso conceptual del slice.)
    uint256 public constant MIN_SET_SIZE = 2;

    /// @notice Fracción del stake que recibe el challenger que prueba fraude, en
    ///         basis points (5000 = 50%). El resto queda RETENIDO en el contrato
    ///         (efectivamente quemado: no hay ruta de retiro). Racional: 50% es
    ///         incentivo suficiente para que existan watchtowers que cacen fraude,
    ///         y retener la otra mitad evita el griefing donde un ASP se
    ///         auto-slashea con un set fraudulento para recuperar su stake vía un
    ///         challenger cómplice (recuperaría a lo sumo la mitad, nunca sale a
    ///         ganancia). El circuito no cambia; esto es puro incentivo económico.
    uint256 public constant SLASH_REWARD_BPS = 5000;

    /// @notice Stake mínimo (wei) para registrar un ASP. Inmutable, fijado por
    ///         constructor. Es la garantía slasheable de Layer 5: si el ASP hace
    ///         fraude, este stake financia la recompensa del challenger.
    uint256 public immutable MIN_STAKE;

    /// @notice Hasher Poseidon(2) on-chain, necesario para recomputar el Merkle
    ///         root de un set dentro de un fraud proof (challengeIntegrity). Es el
    ///         MISMO hasher que usa el pool/árbol, así que la root recomputada
    ///         coincide bit-a-bit con la real.
    IHasher public immutable hasher;

    /// @notice Datos de cada ASP registrado. `owner` == address(0) => no existe.
    /// @dev El historial de roots vive aparte (`aspRoots`) porque un struct no
    ///      puede contener el mapping de la ventana circular.
    struct ASPInfo {
        address owner; // quién administra este ASP (publica sus roots)
        bytes32 policyHash; // hash de la política (propagación + attesters + disputa)
        string metadataURI; // URI con la política legible / metadata del ASP
        uint256 stake; // stake depositado al registrarse (garantía slasheable)
        bool slashed; // marcado por fraud proof (o por governance de emergencia)
        uint256 latestRoot; // última root publicada (conveniencia off-chain)
        bytes32 latestDataHash; // dataHash de la última root (commitment del set)
        uint32 currentRootIndex; // índice vigente en la ventana circular de este ASP
    }

    /// @notice aspId => datos del ASP.
    mapping(uint256 => ASPInfo) public asps;

    /// @notice aspId => (índice circular => association root). Historial reciente
    ///         por-ASP; el valor 0 marca un slot aún no escrito.
    mapping(uint256 => mapping(uint32 => uint256)) internal aspRoots;

    /// @notice aspId => (root => dataHash comprometido para ESA root). Necesario
    ///         para el fraud proof: verifica el challenge contra el commitment de
    ///         la root específica impugnada, no sólo contra la última. `bytes32(0)`
    ///         => esa (aspId, root) nunca fue publicada por este ASP.
    /// @dev No se limpia cuando la root sale de la ventana circular de
    ///      `isKnownRoot`: el compromiso de contenido sobrevive para poder probar
    ///      fraude sobre roots viejas (el fraude no prescribe porque la root ya no
    ///      sirva para retirar).
    mapping(uint256 => mapping(uint256 => bytes32)) public rootDataHash;

    /// @notice Próximo aspId a asignar. Los ids son incrementales desde 1 (el 0
    ///         queda reservado como "no existe").
    uint256 public nextAspId = 1;

    /// @param aspId Id asignado al ASP recién registrado.
    /// @param owner Dirección que administra el ASP.
    /// @param policyHash Hash de la política declarada.
    event ASPRegistered(uint256 indexed aspId, address indexed owner, bytes32 policyHash);

    /// @param aspId ASP que publicó la root.
    /// @param root Association root publicada.
    /// @param dataHash Commitment del set: keccak256(abi.encodePacked(set)).
    event RootPublished(uint256 indexed aspId, uint256 indexed root, bytes32 dataHash);

    /// @param aspId ASP marcado como slashed por el governance de emergencia (backup).
    event ASPSlashed(uint256 indexed aspId);

    /// @param aspId ASP slasheado por un fraud proof verificable.
    /// @param challenger Quien probó el fraude y cobró la recompensa.
    /// @param reward Recompensa transferida al challenger (wei).
    /// @param reason Motivo del slash ("integridad..." / "degenerado...").
    event ASPSlashedByFraud(uint256 indexed aspId, address indexed challenger, uint256 reward, string reason);

    /// @param _minStake Stake mínimo (wei) exigido para registrar un ASP.
    /// @param _governance Owner del registry: sólo dispara el slash() de
    ///        emergencia (backup). El slashing primario es el fraud proof, que NO
    ///        pasa por él.
    /// @param _hasher Hasher Poseidon(2) on-chain, para recomputar Merkle roots en
    ///        los fraud proofs. Debe ser el mismo hasher que usa el pool.
    constructor(uint256 _minStake, address _governance, IHasher _hasher) Ownable(_governance) {
        require(address(_hasher) != address(0), "hasher requerido");
        MIN_STAKE = _minStake;
        hasher = _hasher;
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
    ///      Guarda la root en la ventana circular de ESE ASP, actualiza
    ///      `latestRoot`/`latestDataHash` y REGISTRA el compromiso `rootDataHash`
    ///      (aspId, root) => dataHash para poder verificar fraude sobre ESA root.
    ///      El `dataHash` DEBE ser keccak256(abi.encodePacked(set)) del set de
    ///      commitments que compone la root; publicar cualquier otra cosa deja al
    ///      ASP indefendible ante un challenge (no podrá haber un set que matchee
    ///      el dataHash y a la vez recompute la root).
    /// @param aspId ASP que publica.
    /// @param root Association root construida off-chain (Merkle del set).
    /// @param dataHash keccak256(abi.encodePacked(set)) — commitment del contenido.
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
        rootDataHash[aspId][root] = dataHash;

        emit RootPublished(aspId, root, dataHash);
    }

    /// @notice FRAUD PROOF de integridad: prueba que un ASP publicó una root que
    ///         NO corresponde al set al que se comprometió, y lo slashea.
    /// @dev Flujo: (1) el ASP publicó (root, dataHash) — rootDataHash != 0;
    ///      (2) el challenger provee el `set` cuyo keccak matchea ese dataHash
    ///      (no puede framear con un set arbitrario: si keccak(set) != dataHash,
    ///      revierte); (3) se recomputa el Merkle root de `set` on-chain con el
    ///      mismo hasher/zeros que el árbol real; (4) si NO coincide con la root
    ///      publicada, el ASP mintió → slash + recompensa. Si SÍ coincide, el ASP
    ///      fue honesto y el challenge revierte "sin fraude". `nonReentrant` +
    ///      patrón CEI en _slashByFraud cierran la superficie de reentrancy.
    /// @param aspId ASP impugnado.
    /// @param root Root publicada que se impugna.
    /// @param set Set de commitments que el ASP comprometió vía dataHash.
    function challengeIntegrity(uint256 aspId, uint256 root, uint256[] calldata set) external nonReentrant {
        ASPInfo storage info = asps[aspId];
        require(info.owner != address(0), "ASP inexistente");
        require(!info.slashed, "ASP ya slashed");

        bytes32 committed = rootDataHash[aspId][root];
        require(committed != bytes32(0), "root no publicada por este ASP");
        require(keccak256(abi.encodePacked(set)) == committed, "el set no matchea el dataHash comprometido");

        uint256 recomputed = PoseidonMerkleLib.computeRoot(set, hasher);
        require(recomputed != root, "sin fraude: la root corresponde al set");

        _slashByFraud(aspId, msg.sender, "integridad: root != Merkle(set)");
    }

    /// @notice FRAUD PROOF de set degenerado: prueba que un ASP publicó un set más
    ///         chico que MIN_SET_SIZE (desanonimiza usuarios), y lo slashea.
    /// @dev Verifica el commitment del set (keccak == dataHash de esa root) y que
    ///      `set.length < MIN_SET_SIZE`. Si el set cumple el tamaño mínimo,
    ///      revierte "sin fraude". No recomputa el Merkle root: el fraude acá es el
    ///      TAMAÑO del set comprometido, independiente de si la root cierra.
    /// @param aspId ASP impugnado.
    /// @param root Root publicada que se impugna.
    /// @param set Set de commitments que el ASP comprometió vía dataHash.
    function challengeDegenerate(uint256 aspId, uint256 root, uint256[] calldata set) external nonReentrant {
        ASPInfo storage info = asps[aspId];
        require(info.owner != address(0), "ASP inexistente");
        require(!info.slashed, "ASP ya slashed");

        bytes32 committed = rootDataHash[aspId][root];
        require(committed != bytes32(0), "root no publicada por este ASP");
        require(keccak256(abi.encodePacked(set)) == committed, "el set no matchea el dataHash comprometido");
        require(set.length < MIN_SET_SIZE, "sin fraude: el set cumple el tamano minimo");

        _slashByFraud(aspId, msg.sender, "degenerado: set por debajo del minimo");
    }

    /// @notice Slash de EMERGENCIA por governance (backup, NO el mecanismo primario).
    /// @dev Sólo el owner del REGISTRY. Se conserva por si aparece un fraude que el
    ///      fraud proof on-chain aún no cubre (p.ej. data-withholding, ver
    ///      limitación #1 de la cabecera). No transfiere recompensa (no hay
    ///      challenger); el stake queda retenido. El mecanismo PRIMARIO y
    ///      preferido es challengeIntegrity/challengeDegenerate, que NO requiere
    ///      confianza en el governance.
    /// @param aspId ASP a slashear.
    function slash(uint256 aspId) external onlyOwner {
        ASPInfo storage info = asps[aspId];
        require(info.owner != address(0), "ASP inexistente");
        info.slashed = true;
        emit ASPSlashed(aspId);
    }

    /// @notice Marca slashed, zeroea el stake, transfiere la recompensa y emite.
    /// @dev CEI estricto: se marca slashed y se zeroea el stake ANTES de la
    ///      transferencia externa, de modo que una reentrada volvería a entrar con
    ///      `slashed == true` y revertiría en el require de los challenge. El
    ///      `nonReentrant` de las funciones públicas es una segunda barrera. El
    ///      resto del stake (stake - reward) queda retenido en el contrato.
    /// @param aspId ASP slasheado.
    /// @param challenger Quien cobra la recompensa.
    /// @param reason Motivo (va al evento).
    function _slashByFraud(uint256 aspId, address challenger, string memory reason) internal {
        ASPInfo storage info = asps[aspId];

        // --- Effects (antes de cualquier interacción) ---
        info.slashed = true;
        uint256 stake = info.stake;
        info.stake = 0;
        uint256 reward = (stake * SLASH_REWARD_BPS) / 10000;

        emit ASPSlashedByFraud(aspId, challenger, reward, reason);

        // --- Interaction ---
        if (reward > 0) {
            (bool ok, ) = payable(challenger).call{value: reward}("");
            require(ok, "transferencia de recompensa fallo");
        }
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
