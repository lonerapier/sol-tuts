// SPDX-License-Identifier: MIT
pragma solidity >=0.8.12;

import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";
import {IERC20} from "./interfaces/IERC20.sol";


/// @dev Simple ERC20 vault contract that mints and burn tokens when depositing
/// and withdrawing respectively.
contract Vault3 is MockERC20("Vault3", "VT3", 18) {

	// ============= Custom Errors =============

	error InvalidExchangeRate();
	error Unauthorised();

	// ============== Private Variables ==============

	address private owner;

	// ============== Public State Variables ==============

	uint256 public exchangeRate;
	IERC20 public token;

	// ============== Events ==============

	event Deposit(address indexed depositor, uint256 amount);
	event Withdraw(address indexed withdrawer, uint256 amount);
	event SetExchangeRate(uint256 exchangeRate);

	// ============== Constructor ==============

	constructor(address _token, uint256 _exchangeRate) {
		owner = msg.sender;
		setExchangeRate(_exchangeRate);

		token = IERC20(_token);
	}

	// ============== Private Functions ==============

	function _applyRate(uint256 amount) private view returns (uint256) {
		if (exchangeRate == 0) return amount;

		return (amount * exchangeRate) / 1e18;
	}

	// ============== Public Functions ==============

	function setExchangeRate(uint256 _exchangeRate) public {
		if (msg.sender != owner) revert Unauthorised();
		if (_exchangeRate == 0) revert InvalidExchangeRate();

		exchangeRate = _exchangeRate;

		emit SetExchangeRate(_exchangeRate);
	}


	/// @dev deposit ERC20 tokens to the vault and mint equal vault tokens
	/// @param amount amount of tokens to deposit.
	function deposit(uint256 amount) public returns (uint256 liquidity) {
		liquidity = _applyRate(amount);
		mint(msg.sender, liquidity);

		token.transferFrom(msg.sender, address(this), amount);

		emit Deposit(msg.sender, amount);
	}

	/// @dev withdraw ERC20 tokens from the vault and burn equal vault tokens
	/// @param amount amount of tokens to withdraw.
	function withdraw(uint256 amount) public returns (uint256 liquidity) {
		liquidity = _applyRate(amount);

		burn(msg.sender, liquidity);

		token.transfer(msg.sender, amount);

		emit Withdraw(msg.sender, amount);
	}
}
