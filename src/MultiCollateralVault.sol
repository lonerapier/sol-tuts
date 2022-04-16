// SPDX-License-Identifier: MIT
pragma solidity >=0.8.12;

import {Dai} from "./Dai.sol";
import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {AccessControl} from "@yield-utils/access/AccessControl.sol";

interface IMultiCollateralVault {
    function liquidate(address) external;

    function addNewCollateral(address, address) external;
}

/// @notice Multi-collateralized vault for DAI
/// @dev only owner can add new collateral
contract MultiCollateralVault is AccessControl {
    // ============== Custom Errors ==============

    error InsufficientBalance();
    error InsufficientCollateral();
    error InvalidAmount();
    error InvalidBalance();
    error InvalidCollateral();
    error InvalidExchangeRate();
    error InvalidPriceAndCollateralLength();
    error Unauthorised();
    error Safe();

    // ============== Events ==============

    event Deposit(
        address indexed depositor,
        address _collateral,
        uint256 amount
    );
    event Withdraw(address indexed withdrawer, uint256 amount);
    event Borrow(address indexed borrower, uint256 amount);
    event Repay(address indexed borrower, uint256 amount);
    event Liquidate(address indexed borrower);

    // ============== Public State Variables ==============

    address public immutable owner;
    Dai public immutable dai;
    mapping(address => bool) public activeCollateral;
    mapping(address => address) public tokenPriceFeeds;
    mapping(address => address[]) public userCollaterals;

    // tokens -> user -> amount
    mapping(address => mapping(address => uint256)) public deposits;

    mapping(address => uint256) public loans; // loans is in DAI amount

    // ============== Constructor ==============

    constructor(
        address _owner,
        address _dai,
        // address[] memory _priceFeeds,
        // address[] memory _collaterals,
        address liquidator,
        address collateralManager
    ) {
        _grantRole(IMultiCollateralVault.liquidate.selector, liquidator);
        _grantRole(
            IMultiCollateralVault.addNewCollateral.selector,
            collateralManager
        );
        _grantRole(ROOT, msg.sender);

        owner = _owner;

        dai = Dai(_dai);
    }

    // ============== Private Functions ==============

    /// @notice returns index of an element in array
    /// @dev returns length of array if element not found
    /// @param _array array of addresses
    /// @param _element element to find index of
    /// @return index of array element
    function indexOf(address[] memory _array, address _element)
        private
        pure
        returns (uint256)
    {
        uint256 len = _array.length;
        for (uint256 i; i < len; ++i) {
            if (_array[i] == _element) return i;
        }
        return len;
    }

    /// @notice remove token from user's collateral list
    /// @dev remove when user has no more deposits
    /// @param _collateral collateral address
    function removeUserCollateral(address _collateral) private {
        address[] memory userCollateral = userCollaterals[msg.sender];
        uint256 index = indexOf(userCollateral, _collateral);
        uint256 len = userCollateral.length;
        if (index == len) return;

        userCollaterals[msg.sender][index] = userCollateral[len - 1];
        userCollaterals[msg.sender].pop();
    }

    // ============== Public Functions ==============

    /// @notice apply exchange rate to collateral and amount
    /// @dev keep in check the decimals for respective price feed
    /// @param _collateral collateral address
    /// @param amount amount of collateral to apply exchange rate to
    /// @return amount of collateral in DAI
    function applyExchangeRate(address _collateral, uint256 amount)
        public
        view
        returns (uint256)
    {
        (, int256 exchangeRate, , , ) = AggregatorV3Interface(
            tokenPriceFeeds[_collateral]
        ).latestRoundData();
        if (exchangeRate <= 0) revert InvalidExchangeRate();

        return
            (amount * uint256(exchangeRate)) /
            10**AggregatorV3Interface(tokenPriceFeeds[_collateral]).decimals();
    }

    /// @notice get total deposits for a user
    /// @dev return value is in DAI
    /// @param _guy user address
    /// @return total value of deposits
    function getTotalDepositPrices(address _guy) public view returns (uint256) {
        address[] memory userCollateral = userCollaterals[_guy];

        uint256 len = userCollateral.length;
        uint256 total;

        unchecked {
            for (uint256 i; i < len; ++i)
                total += applyExchangeRate(
                    userCollateral[i],
                    deposits[userCollateral[i]][_guy]
                );
        }

        return total;
    }

    /// @notice deposit accepted collateral to vault
    /// @param _collateral collateral address
    /// @param _amount amount of collateral to deposit
    function deposit(address _collateral, uint256 _amount) external {
        if (!activeCollateral[_collateral]) revert InvalidCollateral();
        if (_amount == 0) revert InvalidAmount();

        uint256 collateralDeposit = deposits[_collateral][msg.sender];

        if (collateralDeposit == 0)
            userCollaterals[msg.sender].push(_collateral);

        unchecked {
            deposits[_collateral][msg.sender] = collateralDeposit + _amount;
        }

        IERC20(_collateral).transferFrom(msg.sender, address(this), _amount);

        emit Deposit(msg.sender, _collateral, _amount);
    }

    /// @notice borrow DAI from vault
    /// @param _daiAmount amount of DAI to borrow
    function borrow(uint256 _daiAmount) external {
        uint256 depositDaiAmount = getTotalDepositPrices(msg.sender);

        uint256 loanAmount = loans[msg.sender];

        if (_daiAmount > (depositDaiAmount - loanAmount))
            revert InsufficientCollateral();

        loans[msg.sender] += _daiAmount;

        dai.transfer(msg.sender, _daiAmount);

        emit Borrow(msg.sender, _daiAmount);
    }

    /// @notice withdraw collateral from vault
    /// @dev need to repay loan first, if withdraw amount is more than balance
    /// i.e. deposits - loans
    /// @param _collateral collateral address
    /// @param _amount amount of collateral to withdraw
    function withdraw(address _collateral, uint256 _amount) external {
        if (!activeCollateral[_collateral]) revert InvalidCollateral();
        if (_amount == 0) revert InvalidAmount();

        uint256 collateralDeposit = deposits[_collateral][msg.sender];
        uint256 depositDaiAmount = getTotalDepositPrices(msg.sender);
        uint256 withdrawDaiAmount = applyExchangeRate(_collateral, _amount);

        if (depositDaiAmount - loans[msg.sender] < withdrawDaiAmount)
            revert InsufficientBalance();

        if (collateralDeposit < _amount) revert InsufficientCollateral();
        if (collateralDeposit - _amount == 0) removeUserCollateral(_collateral);

        unchecked {
            deposits[_collateral][msg.sender] = collateralDeposit - _amount;
        }

        IERC20(_collateral).transferFrom(address(this), msg.sender, _amount);

        emit Withdraw(msg.sender, _amount);
    }

    /// @notice repay loan
    /// @param _daiAmount amount of DAI to repay
    function repay(uint256 _daiAmount) external {
        if (loans[msg.sender] < _daiAmount) revert InvalidBalance();

        unchecked {
            loans[msg.sender] -= _daiAmount;
        }

        dai.transferFrom(msg.sender, address(this), _daiAmount);

        emit Repay(msg.sender, _daiAmount);
    }

    // ============== Restriceted Functions ==============

    /// @notice liquidate all collateral and clear loans of borrower
    /// @dev restriced to owner
    /// @param _borrower borrower address
    function liquidate(address _borrower) external auth {
        if (msg.sender != owner) revert Unauthorised();

        uint256 depositDaiAmount = getTotalDepositPrices(_borrower);
        uint256 loanAmount = loans[_borrower];
        if (depositDaiAmount >= loanAmount) revert Safe();

        address[] memory userCollateral = userCollaterals[_borrower];
        uint256 len = userCollateral.length;
        for (uint256 i; i < len; ++i) {
            delete deposits[userCollateral[i]][_borrower];
        }

        delete userCollaterals[_borrower];

        emit Liquidate(_borrower);
    }

    /// @notice set new active collateral
    /// @dev restriced to owner
    /// @param _token token address
    /// @param _priceFeed price feed address
    function addNewCollateral(address _token, address _priceFeed)
        external
        auth
    {
        // if (msg.sender != owner) revert Unauthorised();

        if (activeCollateral[_token]) revert InvalidCollateral();

        activeCollateral[_token] = true;
        tokenPriceFeeds[_token] = _priceFeed;
    }
}
