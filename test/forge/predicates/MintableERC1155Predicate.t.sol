// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.2;
pragma experimental ABIEncoderV2;

import "test/forge/utils/Test.sol";
import {MintableERC1155Predicate} from "contracts/root/TokenPredicates/MintableERC1155Predicate.sol";
import {DummyMintableERC1155} from "contracts/root/RootToken/DummyMintableERC1155.sol";

contract MintableERC1155PredicateTest is Test {
    MintableERC1155Predicate internal erc1155Predicate;
    DummyMintableERC1155 internal erc1155Token;
    address internal manager = makeAddr("manager");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    uint256 internal tokenId = 0x1337;
    uint256 internal tokenId2 = tokenId % 2;
    uint256 internal amt = 1e4;

    uint256[] internal tokenIds = new uint256[](2);
    uint256[] internal amts = new uint256[](2);

    event RoleGranted(
        bytes32 indexed role,
        address indexed account,
        address indexed sender
    );
    event LockedBatchMintableERC1155(
        address indexed depositor,
        address indexed depositReceiver,
        address indexed rootToken,
        uint256[] ids,
        uint256[] amounts
    );

    event ExitedMintableERC1155(
        address indexed exitor,
        address indexed rootToken,
        uint256 id,
        uint256 amount
    );

    event ExitedBatchMintableERC1155(
        address indexed exitor,
        address indexed rootToken,
        uint256[] ids,
        uint256[] amounts
    );

    function setUp() public {
        tokenIds[0] = tokenId;
        tokenIds[1] = tokenId2;
        amts[0] = amt;
        amts[1] = amt;

        vm.startPrank(manager);
        erc1155Predicate = new MintableERC1155Predicate();
        erc1155Token = new DummyMintableERC1155("ipfs://");
        erc1155Predicate.initialize(manager);

        erc1155Token.grantRole(
            erc1155Token.PREDICATE_ROLE(),
            address(erc1155Predicate)
        );

        // because it's a mintable token, burning it first then
        // brining it to root chain by making predicate contract mint it for us
        string[] memory inputs = new string[](5);
        inputs[0] = "npx";
        inputs[1] = "ts-node";
        inputs[2] = "test/forge/predicates/utils/rlpEncoder.ts";
        inputs[3] = "erc1155TransferBatch";
        inputs[4] = vm.toString(
            abi.encode(
                address(erc1155Predicate) /* operator */,
                alice,
                address(0),
                tokenIds,
                amts,
                erc1155Predicate.TRANSFER_BATCH_EVENT_SIG()
            )
        );
        bytes memory burnLog = vm.ffi(inputs);
        erc1155Predicate.exitTokens(address(erc1155Token), burnLog);

        vm.stopPrank();
        vm.prank(alice);
        erc1155Token.setApprovalForAll(address(erc1155Predicate), true);
    }

    function testAliceBalanceAndApproval() public {
        assertEq(erc1155Token.balanceOf(alice, tokenId), amt);
        assertEq(erc1155Token.balanceOf(address(erc1155Predicate), tokenId), 0);
        assertTrue(
            erc1155Token.isApprovedForAll(alice, address(erc1155Predicate))
        );
        assertFalse(
            erc1155Token.isApprovedForAll(address(erc1155Predicate), alice)
        );
    }

    function testInitialize() public {
        vm.expectRevert("already inited");
        erc1155Predicate.initialize(manager);

        erc1155Predicate = new MintableERC1155Predicate();

        vm.expectEmit();
        emit RoleGranted(
            erc1155Predicate.DEFAULT_ADMIN_ROLE(),
            manager,
            address(this)
        );
        vm.expectEmit();
        emit RoleGranted(
            erc1155Predicate.MANAGER_ROLE(),
            manager,
            address(this)
        );

        erc1155Predicate.initialize(manager);
    }

    function testLockTokensInvalidSender() public {
        bytes memory depositData = abi.encode(tokenIds, amts, new bytes(0));
        vm.expectRevert("MintableERC1155Predicate: INSUFFICIENT_PERMISSIONS");
        erc1155Predicate.lockTokens(
            alice /* depositor */,
            bob /* depositReceiver */,
            address(erc1155Token),
            depositData
        );
    }

    function testLockTokens() public {
        bytes memory depositData = abi.encode(tokenIds, amts, new bytes(0));

        assertEq(erc1155Token.balanceOf(alice, tokenId), amt);
        assertEq(erc1155Token.balanceOf(alice, tokenId2), amt);
        assertEq(erc1155Token.balanceOf(address(erc1155Predicate), tokenId), 0);
        assertEq(
            erc1155Token.balanceOf(address(erc1155Predicate), tokenId2),
            0
        );

        vm.expectEmit();
        emit LockedBatchMintableERC1155(
            alice,
            bob,
            address(erc1155Token),
            tokenIds,
            amts
        );

        vm.prank(manager);
        erc1155Predicate.lockTokens(
            alice,
            bob,
            address(erc1155Token),
            depositData
        );

        assertEq(erc1155Token.balanceOf(alice, tokenId), 0);
        assertEq(erc1155Token.balanceOf(alice, tokenId2), 0);
        assertEq(
            erc1155Token.balanceOf(address(erc1155Predicate), tokenId),
            amt
        );
        assertEq(
            erc1155Token.balanceOf(address(erc1155Predicate), tokenId2),
            amt
        );
        assertEq(erc1155Token.balanceOf(bob, tokenId), 0);
        assertEq(erc1155Token.balanceOf(bob, tokenId2), 0);
    }

    function testLockTokensInsufficientBalance() public {
        bytes memory depositData = abi.encode(tokenIds, amts, new bytes(0));
        vm.expectRevert("ERC1155: transfer caller is not owner nor approved");
        vm.prank(manager);
        erc1155Predicate.lockTokens(
            bob /* depositor */,
            alice /* depositReceiver */,
            address(erc1155Token),
            depositData
        );
    }

    function testExitTokensInvalidSender() public {
        bytes memory depositData = abi.encode(tokenIds, amts, new bytes(0));
        vm.expectRevert("MintableERC1155Predicate: INSUFFICIENT_PERMISSIONS");
        erc1155Predicate.exitTokens(address(erc1155Token), "0x");
    }

    function testExitTokensInsufficientTokensLocked() public {
        string[] memory inputs = new string[](5);
        inputs[0] = "npx";
        inputs[1] = "ts-node";
        inputs[2] = "test/forge/predicates/utils/rlpEncoder.ts";
        inputs[3] = "erc1155TransferSingle";
        inputs[4] = vm.toString(
            abi.encode(
                address(erc1155Predicate) /* operator */,
                alice,
                address(0),
                tokenId,
                amt,
                erc1155Predicate.TRANSFER_SINGLE_EVENT_SIG()
            )
        );
        bytes memory res = vm.ffi(inputs);

        vm.prank(manager);
        erc1155Predicate.exitTokens(address(erc1155Token), res);
    }

    function testExitTokensInvalidSignature() public {
        vm.prank(manager);
        erc1155Predicate.lockTokens(
            alice,
            bob,
            address(erc1155Token),
            abi.encode(tokenIds, amts, new bytes(0))
        );

        string[] memory inputs = new string[](5);
        inputs[0] = "npx";
        inputs[1] = "ts-node";
        inputs[2] = "test/forge/predicates/utils/rlpEncoder.ts";
        inputs[3] = "erc1155TransferSingle";
        inputs[4] = vm.toString(
            abi.encode(
                address(erc1155Predicate),
                alice,
                address(0),
                tokenId,
                amt,
                keccak256("0x1337") /* erc1155Predicate.TRANSFER_EVENT_SIG() */
            )
        );
        bytes memory res = vm.ffi(inputs);

        vm.expectRevert("MintableERC1155Predicate: INVALID_WITHDRAW_SIG");
        vm.prank(manager);
        erc1155Predicate.exitTokens(address(erc1155Token), res);
    }

    function testExitTokensInvalidReceiver() public {
        vm.prank(manager);
        erc1155Predicate.lockTokens(
            alice,
            bob,
            address(erc1155Token),
            abi.encode(tokenIds, amts, new bytes(0))
        );

        string[] memory inputs = new string[](5);
        inputs[0] = "npx";
        inputs[1] = "ts-node";
        inputs[2] = "test/forge/predicates/utils/rlpEncoder.ts";
        inputs[3] = "erc1155TransferSingle";
        inputs[4] = vm.toString(
            abi.encode(
                address(erc1155Predicate) /* operator */,
                alice,
                bob /* address(0) */,
                tokenId,
                amt,
                erc1155Predicate.TRANSFER_SINGLE_EVENT_SIG()
            )
        );
        bytes memory res = vm.ffi(inputs);

        vm.expectRevert("MintableERC1155Predicate: INVALID_RECEIVER");
        vm.prank(manager);
        erc1155Predicate.exitTokens(address(erc1155Token), res);
    }

    function testExitTokens() public {
        assertEq(erc1155Token.balanceOf(alice, tokenId), amt);
        assertEq(erc1155Token.balanceOf(alice, tokenId2), amt);
        assertEq(erc1155Token.balanceOf(address(erc1155Predicate), tokenId), 0);
        assertEq(
            erc1155Token.balanceOf(address(erc1155Predicate), tokenId2),
            0
        );

        vm.prank(manager);
        erc1155Predicate.lockTokens(
            alice,
            bob,
            address(erc1155Token),
            abi.encode(tokenIds, amts, new bytes(0))
        );

        string[] memory inputs = new string[](5);
        inputs[0] = "npx";
        inputs[1] = "ts-node";
        inputs[2] = "test/forge/predicates/utils/rlpEncoder.ts";
        inputs[3] = "erc1155TransferSingle";
        inputs[4] = vm.toString(
            abi.encode(
                address(erc1155Predicate),
                alice,
                address(0),
                tokenId,
                amt,
                erc1155Predicate.TRANSFER_SINGLE_EVENT_SIG()
            )
        );
        bytes memory res = vm.ffi(inputs);

        assertEq(erc1155Token.balanceOf(alice, tokenId), 0);
        assertEq(erc1155Token.balanceOf(alice, tokenId2), 0);
        assertEq(
            erc1155Token.balanceOf(address(erc1155Predicate), tokenId),
            amt
        );
        assertEq(
            erc1155Token.balanceOf(address(erc1155Predicate), tokenId2),
            amt
        );

        vm.expectEmit();
        emit ExitedMintableERC1155(alice, address(erc1155Token), tokenId, amt);
        vm.prank(manager);
        erc1155Predicate.exitTokens(address(erc1155Token), res);

        assertEq(erc1155Token.balanceOf(alice, tokenId), amt);
        assertEq(erc1155Token.balanceOf(alice, tokenId2), 0);
        assertEq(erc1155Token.balanceOf(address(erc1155Predicate), tokenId), 0);
        assertEq(
            erc1155Token.balanceOf(address(erc1155Predicate), tokenId2),
            amt
        );
    }

    function testBatchExitTokens() public {
        assertEq(erc1155Token.balanceOf(alice, tokenId), amt);
        assertEq(erc1155Token.balanceOf(alice, tokenId2), amt);
        assertEq(erc1155Token.balanceOf(address(erc1155Predicate), tokenId), 0);
        assertEq(
            erc1155Token.balanceOf(address(erc1155Predicate), tokenId2),
            0
        );

        vm.prank(manager);
        erc1155Predicate.lockTokens(
            alice,
            bob,
            address(erc1155Token),
            abi.encode(tokenIds, amts, new bytes(0))
        );

        string[] memory inputs = new string[](5);
        inputs[0] = "npx";
        inputs[1] = "ts-node";
        inputs[2] = "test/forge/predicates/utils/rlpEncoder.ts";
        inputs[3] = "erc1155TransferBatch";
        inputs[4] = vm.toString(
            abi.encode(
                address(erc1155Predicate),
                alice,
                address(0),
                tokenIds,
                amts,
                erc1155Predicate.TRANSFER_BATCH_EVENT_SIG()
            )
        );
        bytes memory res = vm.ffi(inputs);

        assertEq(erc1155Token.balanceOf(alice, tokenId), 0);
        assertEq(erc1155Token.balanceOf(alice, tokenId2), 0);
        assertEq(
            erc1155Token.balanceOf(address(erc1155Predicate), tokenId),
            amt
        );
        assertEq(
            erc1155Token.balanceOf(address(erc1155Predicate), tokenId2),
            amt
        );

        vm.expectEmit();
        emit ExitedBatchMintableERC1155(
            alice,
            address(erc1155Token),
            tokenIds,
            amts
        );
        vm.prank(manager);
        erc1155Predicate.exitTokens(address(erc1155Token), res);

        assertEq(erc1155Token.balanceOf(alice, tokenId), amt);
        assertEq(erc1155Token.balanceOf(alice, tokenId2), amt);
        assertEq(erc1155Token.balanceOf(address(erc1155Predicate), tokenId), 0);
        assertEq(
            erc1155Token.balanceOf(address(erc1155Predicate), tokenId2),
            0
        );
    }
}