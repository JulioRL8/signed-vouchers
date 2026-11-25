// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

contract SignedVouchers {
    error InvalidSigner();
    error InvalidVoucher();
    error Expired();
    error NonceUsed();
    error InvalidSignature();
    error TransferFailed();

    struct Voucher {
        address payable recipient;
        uint256 amount;
        uint256 nonce;
        uint256 deadline;
    }

    bytes32 private constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant VOUCHER_TYPEHASH =
        keccak256("Voucher(address recipient,uint256 amount,uint256 nonce,uint256 deadline)");
    bytes32 private constant NAME_HASH = keccak256("SignedVouchers");
    bytes32 private constant VERSION_HASH = keccak256("1");
    uint256 private constant MAX_S = 0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0;

    address public immutable signer;
    mapping(uint256 nonce => bool) public used;

    event Redeemed(uint256 indexed nonce, address indexed recipient, uint256 amount);

    constructor(address authorizer) payable {
        if (authorizer == address(0)) revert InvalidSigner();
        signer = authorizer;
    }

    receive() external payable {}

    function digest(Voucher calldata voucher) public view returns (bytes32) {
        bytes32 domain = keccak256(abi.encode(DOMAIN_TYPEHASH, NAME_HASH, VERSION_HASH, block.chainid, address(this)));
        bytes32 message =
            keccak256(abi.encode(VOUCHER_TYPEHASH, voucher.recipient, voucher.amount, voucher.nonce, voucher.deadline));
        return keccak256(abi.encodePacked(hex"1901", domain, message));
    }

    function redeem(Voucher calldata voucher, uint8 v, bytes32 r, bytes32 s) external {
        if (voucher.recipient == address(0)) revert InvalidVoucher();
        if (voucher.amount == 0) revert InvalidVoucher();
        if (block.timestamp > voucher.deadline) revert Expired();
        if (used[voucher.nonce]) revert NonceUsed();
        if (v != 27 && v != 28) revert InvalidSignature();
        if (uint256(s) > MAX_S) revert InvalidSignature();
        if (ecrecover(digest(voucher), v, r, s) != signer) revert InvalidSignature();

        used[voucher.nonce] = true;
        emit Redeemed(voucher.nonce, voucher.recipient, voucher.amount);
        (bool sent,) = voucher.recipient.call{value: voucher.amount}("");
        if (!sent) revert TransferFailed();
    }
}
