// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {SignedVouchers} from "../src/SignedVouchers.sol";
import {TestBase} from "./TestBase.sol";

contract SignedVouchersTest is TestBase {
    uint256 private constant SIGNING_KEY = 0xA11CE;
    address payable private constant BENEFICIARY = payable(address(0xB0B));
    SignedVouchers private vault;
    SignedVouchers.Voucher private voucher;

    function setUp() public {
        vm.deal(address(this), 10 ether);
        vault = new SignedVouchers{value: 1 ether}(vm.addr(SIGNING_KEY));
        voucher = SignedVouchers.Voucher(BENEFICIARY, 1 ether, 7, block.timestamp + 60);
    }

    function testAcceptsIndependentTypedDataDigestAndPaysOnlyRecipient() public {
        bytes32 domain = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("SignedVouchers")),
                keccak256(bytes("1")),
                block.chainid,
                address(vault)
            )
        );
        bytes32 message = keccak256(
            abi.encode(
                keccak256("Voucher(address recipient,uint256 amount,uint256 nonce,uint256 deadline)"),
                BENEFICIARY,
                uint256(1 ether),
                uint256(7),
                voucher.deadline
            )
        );
        bytes32 expected = keccak256(bytes.concat(hex"1901", domain, message));
        assertEq(vault.digest(voucher), expected);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNING_KEY, expected);

        vm.warp(voucher.deadline);
        vm.prank(address(0xCA01));
        vault.redeem(voucher, v, r, s);
        assertEq(BENEFICIARY.balance, 1 ether);
        assertTrue(vault.used(7));

        vm.expectRevert(SignedVouchers.NonceUsed.selector);
        vault.redeem(voucher, v, r, s);
    }

    function testRejectsZeroSigner() public {
        vm.expectRevert(SignedVouchers.InvalidSigner.selector);
        new SignedVouchers(address(0));
    }

    function testRejectsMalformedVoucherAndExpiry() public {
        SignedVouchers.Voucher memory zeroRecipient = voucher;
        zeroRecipient.recipient = payable(address(0));
        vm.expectRevert(SignedVouchers.InvalidVoucher.selector);
        vault.redeem(zeroRecipient, 27, bytes32(0), bytes32(0));
        SignedVouchers.Voucher memory zeroAmount = voucher;
        zeroAmount.amount = 0;
        vm.expectRevert(SignedVouchers.InvalidVoucher.selector);
        vault.redeem(zeroAmount, 27, bytes32(0), bytes32(0));
        vm.warp(voucher.deadline + 1);
        vm.expectRevert(SignedVouchers.Expired.selector);
        vault.redeem(voucher, 27, bytes32(0), bytes32(0));
    }

    function testRejectsMalformedAndUnauthorizedSignatures() public {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xBAD, vault.digest(voucher));
        vm.expectRevert(SignedVouchers.InvalidSignature.selector);
        vault.redeem(voucher, 29, r, s);
        vm.expectRevert(SignedVouchers.InvalidSignature.selector);
        vault.redeem(voucher, v, r, bytes32(type(uint256).max));
        vm.expectRevert(SignedVouchers.InvalidSignature.selector);
        vault.redeem(voucher, v, r, s);
        assertTrue(!vault.used(7));
    }

    function testSignatureCannotCrossVaultOrChainDomains() public {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNING_KEY, vault.digest(voucher));
        SignedVouchers other = new SignedVouchers(vm.addr(SIGNING_KEY));
        vm.expectRevert(SignedVouchers.InvalidSignature.selector);
        other.redeem(voucher, v, r, s);
        vm.chainId(block.chainid + 1);
        vm.expectRevert(SignedVouchers.InvalidSignature.selector);
        vault.redeem(voucher, v, r, s);
    }

    function testRecipientAndAmountAreBoundBySignature() public {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNING_KEY, vault.digest(voucher));
        SignedVouchers.Voucher memory changed = voucher;
        changed.recipient = payable(address(0xCA01));
        vm.expectRevert(SignedVouchers.InvalidSignature.selector);
        vault.redeem(changed, v, r, s);
        changed = voucher;
        changed.amount += 1;
        vm.expectRevert(SignedVouchers.InvalidSignature.selector);
        vault.redeem(changed, v, r, s);
    }

    function testRevertedPayoutRollsBackNonceAndAllowsRetry() public {
        voucher.amount = 2 ether;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNING_KEY, vault.digest(voucher));
        vm.expectRevert(SignedVouchers.TransferFailed.selector);
        vault.redeem(voucher, v, r, s);
        assertTrue(!vault.used(voucher.nonce));

        (bool sent,) = address(vault).call{value: 1 ether}("");
        assertTrue(sent);
        vault.redeem(voucher, v, r, s);
        assertEq(BENEFICIARY.balance, 2 ether);
    }
}
