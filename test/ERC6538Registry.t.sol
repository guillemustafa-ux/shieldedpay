// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC6538Registry} from "../src/ERC6538Registry.sol";

contract ERC6538RegistryTest is Test {
    ERC6538Registry internal registry;

    // Claves de un registrant "con billetera real" (necesitamos la privkey
    // para firmar EIP-712 con vm.sign en los tests de registerKeysOnBehalf).
    uint256 internal alicePk = 0xA11CE;
    address internal alice;

    address internal bob = makeAddr("bob");
    address internal relayer = makeAddr("relayer");

    bytes32 internal constant REGISTER_TYPEHASH =
        keccak256("RegisterKeysOnBehalf(address registrant,uint256 schemeId,uint256 nonce,bytes stealthMetaAddress)");

    function setUp() public {
        registry = new ERC6538Registry();
        alice = vm.addr(alicePk);
    }

    // ---- helpers ----

    /// @dev Reconstruye a mano el digest EIP-712 que el contrato espera,
    ///      usando el nonce ACTUAL de `registrant` (igual que hace la lógica
    ///      interna de `registerKeysOnBehalf`).
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

    function _sign(uint256 pk, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    // ---- registerKeys ----

    function test_RegisterKeys_StoresAndReads() public {
        bytes memory metaAddress = hex"0201aa02bb";

        vm.prank(alice);
        vm.expectEmit(true, true, false, true, address(registry));
        emit ERC6538Registry.StealthMetaAddressSet(alice, 1, metaAddress);
        registry.registerKeys(1, metaAddress);

        assertEq(registry.stealthMetaAddressOf(alice, 1), metaAddress, "meta-address no coincide");
    }

    function test_RegisterKeys_OverwritesPreviousValue() public {
        vm.startPrank(alice);
        registry.registerKeys(1, hex"01");
        registry.registerKeys(1, hex"02");
        vm.stopPrank();

        assertEq(registry.stealthMetaAddressOf(alice, 1), hex"02", "debe quedar el ultimo valor registrado");
    }

    function test_RegisterKeys_DifferentSchemeIdsDontCollide() public {
        vm.startPrank(alice);
        registry.registerKeys(1, hex"aaaa");
        registry.registerKeys(2, hex"bbbb");
        vm.stopPrank();

        assertEq(registry.stealthMetaAddressOf(alice, 1), hex"aaaa");
        assertEq(registry.stealthMetaAddressOf(alice, 2), hex"bbbb");
    }

    function test_RegisterKeys_DifferentRegistrantsDontCollide() public {
        vm.prank(alice);
        registry.registerKeys(1, hex"aaaa");

        vm.prank(bob);
        registry.registerKeys(1, hex"bbbb");

        assertEq(registry.stealthMetaAddressOf(alice, 1), hex"aaaa");
        assertEq(registry.stealthMetaAddressOf(bob, 1), hex"bbbb");
    }

    function test_RegisterKeys_DoesNotChangeNonce() public {
        vm.prank(alice);
        registry.registerKeys(1, hex"aaaa");
        assertEq(registry.nonceOf(alice), 0, "registerKeys directo no consume nonce");
    }

    // ---- registerKeysOnBehalf: caso feliz ----

    function test_RegisterKeysOnBehalf_ValidSignature() public {
        bytes memory metaAddress = hex"0301aa02bb";
        uint256 nonce = registry.nonceOf(alice);
        bytes32 digest = _digest(alice, 1, metaAddress, nonce);
        bytes memory signature = _sign(alicePk, digest);

        vm.prank(relayer);
        vm.expectEmit(true, true, false, true, address(registry));
        emit ERC6538Registry.StealthMetaAddressSet(alice, 1, metaAddress);
        registry.registerKeysOnBehalf(alice, 1, signature, metaAddress);

        assertEq(registry.stealthMetaAddressOf(alice, 1), metaAddress);
    }

    function test_RegisterKeysOnBehalf_IncrementsNonce() public {
        bytes memory metaAddress = hex"04";
        bytes32 digest = _digest(alice, 1, metaAddress, 0);
        bytes memory signature = _sign(alicePk, digest);

        registry.registerKeysOnBehalf(alice, 1, signature, metaAddress);

        assertEq(registry.nonceOf(alice), 1, "nonce debe incrementar tras un registro exitoso");
    }

    function test_RegisterKeysOnBehalf_AnyoneCanRelay() public {
        bytes memory metaAddress = hex"05";
        bytes32 digest = _digest(alice, 1, metaAddress, 0);
        bytes memory signature = _sign(alicePk, digest);

        // bob paga el gas y relayea la firma de alice; el registrant sigue siendo alice.
        vm.prank(bob);
        registry.registerKeysOnBehalf(alice, 1, signature, metaAddress);

        assertEq(registry.stealthMetaAddressOf(alice, 1), metaAddress);
    }

    /// @notice Tras consumir una firma, la misma firma ya no sirve para un
    ///         segundo registro (el nonce vigente cambió y el digest ya no matchea).
    function test_RegisterKeysOnBehalf_SignatureCannotBeReplayed() public {
        bytes memory metaAddress = hex"06";
        bytes32 digest = _digest(alice, 1, metaAddress, 0);
        bytes memory signature = _sign(alicePk, digest);

        registry.registerKeysOnBehalf(alice, 1, signature, metaAddress);

        vm.expectRevert(ERC6538Registry.InvalidSignature.selector);
        registry.registerKeysOnBehalf(alice, 1, signature, metaAddress);
    }

    // ---- registerKeysOnBehalf: reverts ----

    function test_RegisterKeysOnBehalf_RevertsIfInvalidSigner() public {
        bytes memory metaAddress = hex"07";
        uint256 bobPk = 0xB0B;
        bytes32 digest = _digest(alice, 1, metaAddress, 0);
        // Firmado por bob, pero el registrant declarado es alice.
        bytes memory signature = _sign(bobPk, digest);

        vm.expectRevert(ERC6538Registry.InvalidSignature.selector);
        registry.registerKeysOnBehalf(alice, 1, signature, metaAddress);
    }

    function test_RegisterKeysOnBehalf_RevertsIfWrongSchemeIdSigned() public {
        bytes memory metaAddress = hex"08";
        // alice firma para schemeId=2, pero se intenta registrar bajo schemeId=1.
        bytes32 digest = _digest(alice, 2, metaAddress, 0);
        bytes memory signature = _sign(alicePk, digest);

        vm.expectRevert(ERC6538Registry.InvalidSignature.selector);
        registry.registerKeysOnBehalf(alice, 1, signature, metaAddress);
    }

    function test_RegisterKeysOnBehalf_RevertsIfWrongMetaAddressSigned() public {
        bytes32 digest = _digest(alice, 1, hex"aaaa", 0);
        bytes memory signature = _sign(alicePk, digest);

        // se intenta colar una meta-address distinta a la firmada.
        vm.expectRevert(ERC6538Registry.InvalidSignature.selector);
        registry.registerKeysOnBehalf(alice, 1, signature, hex"bbbb");
    }

    /// @notice Una firma armada con un nonce que no es el vigente (ej. una
    ///         futura, o una vieja ya consumida) revierte con InvalidSignature,
    ///         porque el contrato siempre recomputa el digest con
    ///         `nonceOf[registrant]` actual, no con el nonce que el firmante
    ///         creyó usar.
    function test_RegisterKeysOnBehalf_RevertsIfWrongNonceSigned() public {
        bytes memory metaAddress = hex"09";
        // el nonce vigente de alice es 0, pero firma como si ya fuera 1.
        bytes32 digest = _digest(alice, 1, metaAddress, 1);
        bytes memory signature = _sign(alicePk, digest);

        vm.expectRevert(ERC6538Registry.InvalidSignature.selector);
        registry.registerKeysOnBehalf(alice, 1, signature, metaAddress);
    }

    function test_RegisterKeysOnBehalf_RevertsOnMalformedSignature() public {
        vm.expectRevert();
        registry.registerKeysOnBehalf(alice, 1, hex"deadbeef", hex"09");
    }

    // ---- fuzz ----

    /// @notice Para cualquier schemeId y cualquier stealthMetaAddress (largo
    ///         variable), una firma EIP-712 válida de `alice` siempre resulta
    ///         en un registro exitoso con esos mismos valores.
    function testFuzz_RegisterKeysOnBehalf_ValidSignatureAlwaysSucceeds(uint256 schemeId, bytes memory metaAddress)
        public
    {
        uint256 nonce = registry.nonceOf(alice);
        bytes32 digest = _digest(alice, schemeId, metaAddress, nonce);
        bytes memory signature = _sign(alicePk, digest);

        registry.registerKeysOnBehalf(alice, schemeId, signature, metaAddress);

        assertEq(registry.stealthMetaAddressOf(alice, schemeId), metaAddress);
        assertEq(registry.nonceOf(alice), nonce + 1);
    }

    function testFuzz_RegisterKeys_StoresArbitraryBytes(uint256 schemeId, bytes memory metaAddress) public {
        vm.prank(alice);
        registry.registerKeys(schemeId, metaAddress);

        assertEq(registry.stealthMetaAddressOf(alice, schemeId), metaAddress);
    }
}
