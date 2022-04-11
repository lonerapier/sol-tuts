// SPDX-License-Identifier: MIT
pragma solidity >=0.8.12;

import {IERC20} from "./interfaces/IERC20.sol";

contract Vault1 {
	// ============== Custom Errors ==============

	error InsufficientBalance();

	// ============== Public State Variables ==============
	IERC20 public token;
	mapping(address => uint256) public balances;

	// ============== Events ==============
	event Deposit(address indexed depositor, uint256 amount);
	event Withdraw(address indexed withdrawer, uint256 amount);

	// ============== Constructor ==============
	constructor(address _token) {
		token = IERC20(_token);
	}

	// ============== Public Functions ==============

	/// @dev deposit ERC20 tokens to the vault.
	/// @param amount amount of tokens to deposit.
	function deposit(uint256 amount) public {
		balances[msg.sender] += amount;
		token.transferFrom(msg.sender, address(this), amount);

		emit Deposit(msg.sender, amount);
	}

	/// @dev withdraw ERC20 tokens from the vault.
	/// @param amount amount of tokens to withdraw.
	function withdraw(uint256 amount) public {
		if (balances[msg.sender] < amount) revert InsufficientBalance();

		balances[msg.sender] -= amount;
		token.transfer(msg.sender, amount);

		emit Withdraw(msg.sender, amount);
	}
}