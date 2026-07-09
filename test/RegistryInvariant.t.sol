// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {ERC6538Registry} from "../src/ERC6538Registry.sol";

/// @dev Handler con actores fijos (privkeys conocidas, para poder firmar
///      EIP-712 igual que haría una wallet real) y un set fijo de schemeIds,
///      para que el fuzzer explore secuencias realistas de
///      `registerKeys` / `registerKeysOnBehalf` sobre los mismos (actor, scheme).
///
///      Guarda además un "ghost state" (`lastRegistered`) con lo último que
///      efectivamente se logró registrar para cada (actor, schemeId), que el
///      invariant usa como oráculo independiente del propio getter.
contract ERC6538RegistryHandler is Test {
    ERC6538Registry public registry;

    uint256[] internal actorPks;
    address[] internal actors;
    uint256[] internal schemeIds;

    mapping(address => mapping(uint256 => bytes)) public lastRegistered;
    mapping(address => mapping(uint256 => bool)) public wasEverSet;

    bytes32 internal constant REGISTER_TYPEHASH =
        keccak256("RegisterKeysOnBehalf(address registrant,uint256 schemeId,uint256 nonce,bytes stealthMetaAddress)");

    constructor(ERC6538Registry _registry) {
        registry = _registry;
        for (uint256 i = 0; i < 4; i++) {
            uint256 pk = uint256(keccak256(abi.encodePacked("registryInvariantActor", i))) % (2 ** 128);
            if (pk == 0) pk = 1;
            actorPks.push(pk);
            actors.push(vm.addr(pk));
        }
        schemeIds = [uint256(1), uint256(2), uint256(3)];
    }

    function actorsLength() external view returns (uint256) {
        return actors.length;
    }

    function actorAt(uint256 i) external view returns (address) {
        return actors[i];
    }

    function schemeIdsLength() external view returns (uint256) {
        return schemeIds.length;
    }

    function schemeIdAt(uint256 i) external view returns (uint256) {
        return schemeIds[i];
    }

    /// @dev Replica el digest EIP-712 que arma internamente el registry, para
    ///      poder firmar como lo haría la wallet del actor.
    function _digest(address registrant, uint256 schemeId, bytes memory metaAddress, uint256 nonce)
        internal
        view
        returns (bytes32)
    {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("ERC6538Registry")),
                keccak256(bytes("1.0")),
                block.chainid,
                address(registry)
            )
        );
        bytes32 structHash =
            keccak256(abi.encode(REGISTER_TYPEHASH, registrant, schemeId, nonce, keccak256(metaAddress)));
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    function registerKeys(uint256 actorSeed, uint256 schemeSeed, bytes memory metaAddress) external {
        address actor = actors[actorSeed % actors.length];
        uint256 schemeId = schemeIds[schemeSeed % schemeIds.length];

        vm.prank(actor);
        registry.registerKeys(schemeId, metaAddress);

        lastRegistered[actor][schemeId] = metaAddress;
        wasEverSet[actor][schemeId] = true;
    }

    function registerKeysOnBehalf(uint256 actorSeed, uint256 schemeSeed, bytes memory metaAddress) external {
        uint256 idx = actorSeed % actors.length;
        address actor = actors[idx];
        uint256 schemeId = schemeIds[schemeSeed % schemeIds.length];

        uint256 nonce = registry.nonceOf(actor);
        bytes32 digest = _digest(actor, schemeId, metaAddress, nonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(actorPks[idx], digest);

        registry.registerKeysOnBehalf(actor, schemeId, abi.encodePacked(r, s, v), metaAddress);

        lastRegistered[actor][schemeId] = metaAddress;
        wasEverSet[actor][schemeId] = true;
    }
}

/// @title Invariant test — ERC6538Registry: nonces monótonos y el getter nunca miente
/// @notice Dos propiedades que DEBEN sostenerse tras cualquier secuencia
///         aleatoria de `registerKeys` / `registerKeysOnBehalf`:
///
///         1. El `nonceOf` de un registrant nunca decrece (protección
///            anti-replay: solo puede subir, nunca resetearse ni retroceder).
///         2. `stealthMetaAddressOf(actor, schemeId)` siempre devuelve
///            exactamente los bytes del último registro que tuvo éxito para
///            ese (actor, schemeId) — el storage nunca "pierde" ni "mezcla"
///            un registro con otro.
contract RegistryInvariantTest is StdInvariant, Test {
    ERC6538Registry internal registry;
    ERC6538RegistryHandler internal handler;

    mapping(address => uint256) internal lastSeenNonce;

    function setUp() public {
        registry = new ERC6538Registry();
        handler = new ERC6538RegistryHandler(registry);

        targetContract(address(handler));
    }

    function invariant_NonceNeverDecreases() public {
        uint256 n = handler.actorsLength();
        for (uint256 i = 0; i < n; i++) {
            address actor = handler.actorAt(i);
            uint256 current = registry.nonceOf(actor);
            assertGe(current, lastSeenNonce[actor], "el nonce de un registrant nunca puede decrecer");
            lastSeenNonce[actor] = current;
        }
    }

    function invariant_GetterMatchesLastRegistered() public view {
        uint256 nActors = handler.actorsLength();
        uint256 nSchemes = handler.schemeIdsLength();
        for (uint256 i = 0; i < nActors; i++) {
            address actor = handler.actorAt(i);
            for (uint256 j = 0; j < nSchemes; j++) {
                uint256 schemeId = handler.schemeIdAt(j);
                if (!handler.wasEverSet(actor, schemeId)) continue;

                assertEq(
                    registry.stealthMetaAddressOf(actor, schemeId),
                    handler.lastRegistered(actor, schemeId),
                    "el getter debe devolver siempre lo ultimo registrado"
                );
            }
        }
    }
}
