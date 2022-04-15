// SPDX-License-Identifier: MIT
pragma solidity >=0.8.12;

import {Dai} from "./Dai.sol";
import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";

/// @notice vault for single collateral type namely ETH
contract CollateralizedVault {
    // ============== Custom Errors ==============

    error InsufficientBalance();
    error InsufficientCollateral();
    error InvalidAmount();
    error InvalidExchangeRate();
    error Unauthorised();
    error Safe();

    // ============== Events ==============

    event Deposit(address indexed depositor, uint256 amount);
    event Withdraw(address indexed withdrawer, uint256 amount);
    event Borrow(address indexed borrower, uint256 amount);
    event Repay(address indexed borrower, uint256 amount);
    event Liquidate(address indexed borrower);

    // ============== Public State Variables ==============

    address public immutable owner;
    Dai public immutable token;
    AggregatorV3Interface public immutable oracle;

    mapping(address => uint256) public deposits; // deposits is in ETH amount
    mapping(address => uint256) public loans; // loans is in DAI amount

    // ============== Constructor ==============

    constructor(address _token, address _oracle) {
        owner = msg.sender;

        token = Dai(_token);

        oracle = AggregatorV3Interface(_oracle);
    }

    // ============== Public Functions ==============

    function applyExchangeRate(uint256 amount) public view returns (uint256) {
        (, int256 exchangeRate, , , ) = oracle.latestRoundData();
        if (exchangeRate <= 0) revert InvalidExchangeRate();

        return (amount * uint256(exchangeRate)) / 1e18;
    }

    /// @notice deposits ETH into the vault
    function deposit() external payable {
        deposits[msg.sender] += msg.value;

        emit Deposit(msg.sender, msg.value);
    }

    /// @notice borrow DAI against ETH deposits
    /// @param _daiAmount amount of DAI to borrow
    function borrow(uint256 _daiAmount) external {
        uint256 depositDaiAmount = applyExchangeRate(deposits[msg.sender]);

        uint256 loanAmount = loans[msg.sender];

        if (_daiAmount > (depositDaiAmount - loanAmount))
            revert InsufficientCollateral();

        loans[msg.sender] += _daiAmount;

        token.transfer(msg.sender, _daiAmount);

        emit Borrow(msg.sender, _daiAmount);
    }

    /// @notice withdraw deposited collateral
    /// @dev need to repay loan first, if withdraw amount is more than balance
    /// i.e. deposits - loans
    /// @param _ethAmount amount of ETH to withdraw
    function withdraw(uint256 _ethAmount) external {
        if (_ethAmount > deposits[msg.sender]) revert InsufficientBalance();

        uint256 depositDaiAmount = applyExchangeRate(deposits[msg.sender]);
        uint256 withdrawDaiAmount = applyExchangeRate(_ethAmount);

        if (depositDaiAmount - loans[msg.sender] < withdrawDaiAmount)
            revert InsufficientBalance();
        unchecked {
            deposits[msg.sender] -= _ethAmount;
        }

        payable(msg.sender).transfer(_ethAmount);
    }

    /// @notice repay loan
    /// @param _daiAmount amount of loaned DAI to repay
    function repay(uint256 _daiAmount) external {
        if (_daiAmount > loans[msg.sender]) revert InvalidAmount();

        unchecked {
            loans[msg.sender] -= _daiAmount;
        }

        token.transferFrom(msg.sender, address(this), _daiAmount);

        emit Repay(msg.sender, _daiAmount);
    }

    // ============== Restricted Functions ==============

    /// @notice liquidate all collateral and loan if balance decreases a threshold
    /// @dev can only be called by owner
    /// @param borrower address of the borrower
    function liquidate(address borrower) external {
        if (msg.sender != owner) revert Unauthorised();

        uint256 depositDaiAmount = applyExchangeRate(deposits[borrower]);

        if (depositDaiAmount >= loans[borrower]) revert Safe();

        delete deposits[borrower];
        delete loans[borrower];
        emit Liquidate(borrower);
    }
}
