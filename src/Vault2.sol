// SPDX-License-Identifier: MIT
pragma solidity >=0.8.12;

import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";
import {IERC20} from "./interfaces/IERC20.sol";


/// @dev Simple ERC20 vault contract that mints and burn tokens when depositing
/// and withdrawing respectively.
contract Vault2 is MockERC20("Vault2", "VT2", 18) {

	// ============== Public State Variables ==============

	IERC20 public token;

	// ============== Events ==============

	event Deposit(address indexed depositor, uint256 amount);
	event Withdraw(address indexed withdrawer, uint256 amount);

	// ============== Constructor ==============

	constructor(address _token) {
		token = IERC20(_token);
	}

	// ============== Public Functions ==============

	/// @dev deposit ERC20 tokens to the vault and mint equal vault tokens
	/// @param amount amount of tokens to deposit.
	function deposit(uint256 amount) public {
		mint(msg.sender, amount);

		token.transferFrom(msg.sender, address(this), amount);

		emit Deposit(msg.sender, amount);
	}

	/// @dev withdraw ERC20 tokens from the vault and burn equal vault tokens
	/// @param amount amount of tokens to withdraw.
	function withdraw(uint256 amount) public {
		burn(msg.sender, amount);

		token.transfer(msg.sender, amount);

		emit Withdraw(msg.sender, amount);
	}
}
