// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

/**
 * @title SimplePermit2
 * @notice A simple implementation of Permit2 for local testing that actually transfers tokens
 */
contract SimplePermit2 is IAllowanceTransfer {
    mapping(address => mapping(address => mapping(address => PackedAllowance))) internal _allowance;
    mapping(address => uint256) public nonceBitmap;

    function allowance(address user, address token, address spender)
        external
        view
        returns (uint160 amount, uint48 expiration, uint48 nonce)
    {
        PackedAllowance memory allowed = _allowance[user][token][spender];
        return (allowed.amount, allowed.expiration, allowed.nonce);
    }

    function approve(address token, address spender, uint160 amount, uint48 expiration) external {
        _allowance[msg.sender][token][spender] = PackedAllowance({amount: amount, expiration: expiration, nonce: 0});
        emit Approval(msg.sender, token, spender, amount, expiration);
    }

    function permit(address owner, PermitSingle memory permitSingle, bytes calldata) external {
        _allowance[owner][permitSingle.details.token][msg.sender] = PackedAllowance({
            amount: permitSingle.details.amount,
            expiration: permitSingle.details.expiration,
            nonce: permitSingle.details.nonce
        });
        emit Permit(
            owner,
            permitSingle.details.token,
            msg.sender,
            permitSingle.details.amount,
            permitSingle.details.expiration,
            permitSingle.details.nonce
        );
    }

    function permit(address owner, PermitBatch memory permitBatch, bytes calldata) external {
        for (uint256 i = 0; i < permitBatch.details.length; i++) {
            _allowance[owner][permitBatch.details[i].token][permitBatch.spender] = PackedAllowance({
                amount: permitBatch.details[i].amount,
                expiration: permitBatch.details[i].expiration,
                nonce: permitBatch.details[i].nonce
            });
        }
    }

    function transferFrom(address from, address to, uint160 amount, address token) external {
        // For testing: simple direct transfer using our allowance
        IERC20(token).transferFrom(from, to, uint256(amount));
    }

    function transferFrom(AllowanceTransferDetails[] calldata transferDetails) external {
        for (uint256 i = 0; i < transferDetails.length; i++) {
            IERC20(transferDetails[i].token).transferFrom(
                transferDetails[i].from, transferDetails[i].to, uint256(transferDetails[i].amount)
            );
        }
    }

    function lockdown(TokenSpenderPair[] calldata approvals) external {
        for (uint256 i = 0; i < approvals.length; i++) {
            _allowance[msg.sender][approvals[i].token][approvals[i].spender] =
                PackedAllowance({amount: 0, expiration: 0, nonce: 0});
            emit Lockdown(msg.sender, approvals[i].token, approvals[i].spender);
        }
    }

    function invalidateNonces(address token, address spender, uint48 newNonce) external {
        PackedAllowance storage allowed = _allowance[msg.sender][token][spender];
        uint48 oldNonce = allowed.nonce;
        allowed.nonce = newNonce;
        emit NonceInvalidation(msg.sender, token, spender, newNonce, oldNonce);
    }

    function invalidateUnorderedNonces(uint256 wordPos, uint256 mask) external {
        nonceBitmap[msg.sender] ^= mask << wordPos;
    }

    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return keccak256("SIMPLE_PERMIT2");
    }
}
