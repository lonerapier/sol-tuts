// SPDX-License-Identifier: MIT
pragma solidity >=0.8.12;

import {CollateralizedVault} from "../CollateralizedVault.sol";
import {Dai} from "../Dai.sol";
import {MockPriceFeed} from "../MockPriceFeed.sol";
import {DSTestPlus} from "./utils/DSTestPlus.sol";

contract TestCollateralizedVault is DSTestPlus {
    address public constant vaultOwner = address(0xabcd);
    address public constant mockUser = address(0x1234);
    uint256 public constant INITIAL_VAULT_DAI_BALANCE = 10000000000000000000000;
    uint256 public constant INITIAL_SETUP_BALANCE = 100 ether;
    int256 public constant INITIAL_EXCHANGE_RATE = 300000000000;

    uint256 public constant CHAIN_ID = 4;
    Dai public dai;
    MockPriceFeed public priceFeed;
    CollateralizedVault public vault;

    function setUp() public {
        dai = new Dai(CHAIN_ID);
        priceFeed = new MockPriceFeed(INITIAL_EXCHANGE_RATE, 18);

        vm.prank(vaultOwner);
        vault = new CollateralizedVault(address(dai), address(priceFeed));
    }

    function _setUpBalances() private {
        vm.deal(address(this), INITIAL_SETUP_BALANCE);
        dai.mint(address(vault), INITIAL_VAULT_DAI_BALANCE);
    }

    function testDeposit() public {
        _setUpBalances();

        vault.deposit{value: 10 ether}();

        assertEq(vault.deposits(address(this)), 10 ether);
        assertEq(address(this).balance, INITIAL_SETUP_BALANCE - 10 ether);
    }

    function testDepositMultipleDeposits() public {
        _setUpBalances();

        vault.deposit{value: 10 ether}();
        vault.deposit{value: 20 ether}();

        assertEq(vault.deposits(address(this)), 30 ether);
        assertEq(address(this).balance, INITIAL_SETUP_BALANCE - 30 ether);
    }

    function testDepositMultipleAddress() public {
        _setUpBalances();

        vault.deposit{value: 10 ether}();

        vm.deal(mockUser, 20 ether);
        vm.prank(mockUser);
        vault.deposit{value: 20 ether}();

        assertEq(vault.deposits(address(this)), 10 ether);
        assertEq(vault.deposits(mockUser), 20 ether);
        assertEq(address(this).balance, INITIAL_SETUP_BALANCE - 10 ether);
        assertEq(mockUser.balance, 0 ether);
    }

    function testDepositZero() public {
        _setUpBalances();

        vault.deposit();

        assertEq(vault.deposits(address(this)), 0);
        assertEq(address(this).balance, INITIAL_SETUP_BALANCE);
    }

    function testDepositFuzz(uint256 amount) public {
        vm.deal(address(this), amount);
        vault.deposit{value: amount}();

        assertEq(vault.deposits(address(this)), amount);
        assertEq(address(this).balance, 0);
    }

    function testDepositMultipleFuzz(uint256 amount) public {
        vm.assume(amount < type(uint256).max >> 1);
        vm.deal(address(this), 2 * amount);

        vault.deposit{value: amount}();
        vault.deposit{value: amount}();

        assertEq(vault.deposits(address(this)), amount * 2);
    }

    function testApplyExchangeRate() public {
        uint256 amount = vault.applyExchangeRate(1 ether);
        assertEq(amount, uint256(INITIAL_EXCHANGE_RATE * 1 ether) / 1e18);
    }

    function testApplyExchangeRateFuzz(uint256 amount) public {
        vm.assume(amount < type(uint256).max / uint256(INITIAL_EXCHANGE_RATE));

        uint256 expected = uint256(INITIAL_EXCHANGE_RATE) * amount;
        uint256 actual = vault.applyExchangeRate(amount);

        assertEq(actual, expected / 1e18);
    }

    function testBorrow() public {
        _setUpBalances();

        vault.deposit{value: 10 ether}();

        uint256 loanAmount = 10 * uint256(INITIAL_EXCHANGE_RATE);
        vault.borrow(loanAmount);

        assertEq(vault.loans(address(this)), loanAmount);
        assertEq(dai.balanceOf(address(this)), loanAmount);
        assertEq(
            dai.balanceOf(address(vault)),
            INITIAL_VAULT_DAI_BALANCE - loanAmount
        );
    }

    function testBorrowPartial() public {
        _setUpBalances();

        vault.deposit{value: 10 ether}();

        uint256 partialLoanAmount = (10 * uint256(INITIAL_EXCHANGE_RATE)) >> 1;
        vault.borrow(partialLoanAmount);

        assertEq(vault.loans(address(this)), partialLoanAmount);
        assertEq(dai.balanceOf(address(this)), partialLoanAmount);
        assertEq(
            dai.balanceOf(address(vault)),
            INITIAL_VAULT_DAI_BALANCE - partialLoanAmount
        );
    }

    function testBorrowMultiple() public {
        _setUpBalances();

        vault.deposit{value: 10 ether}();

        uint256 totalLoanAmount = 10 * uint256(INITIAL_EXCHANGE_RATE);
        uint256 partialLoanAmount = totalLoanAmount >> 1;

        vault.borrow(partialLoanAmount);
        vault.borrow(partialLoanAmount);

        assertEq(vault.loans(address(this)), totalLoanAmount);
        assertEq(dai.balanceOf(address(this)), totalLoanAmount);
        assertEq(
            dai.balanceOf(address(vault)),
            INITIAL_VAULT_DAI_BALANCE - totalLoanAmount
        );
    }

    function testBorrowInsufficientCollateral() public {
        _setUpBalances();

        vault.deposit{value: 10 ether}();

        uint256 totalLoanAmount = 10 * uint256(INITIAL_EXCHANGE_RATE);
        uint256 partialLoanAmount = totalLoanAmount >> 1;

        vault.borrow(partialLoanAmount);

        vm.expectRevert(abi.encodeWithSignature("InsufficientCollateral()"));
        vault.borrow(partialLoanAmount + 1);

        assertEq(vault.loans(address(this)), partialLoanAmount);
        assertEq(dai.balanceOf(address(this)), partialLoanAmount);
        assertEq(
            dai.balanceOf(address(vault)),
            INITIAL_VAULT_DAI_BALANCE - partialLoanAmount
        );
    }

    function testBorrowAppreciateETH() public {
        _setUpBalances();

        vault.deposit{value: 10 ether}();

        // set new rate
        priceFeed.modifyExchangeRate(320000000000);
        (, int256 exchangeRate, , , ) = priceFeed.latestRoundData();

        uint256 loanAmount = 10 * uint256(exchangeRate);

        vault.borrow(loanAmount);

        assertEq(vault.loans(address(this)), loanAmount);
        assertEq(dai.balanceOf(address(this)), loanAmount);
        assertEq(
            dai.balanceOf(address(vault)),
            INITIAL_VAULT_DAI_BALANCE - loanAmount
        );
    }

    function testBorrowMultipleAppreciateETH() public {
        _setUpBalances();
        uint256 totalDepositETH = 10;
        uint256 partialLoanAmountETH = 5;

        vault.deposit{value: 10 ether}();

        uint256 partialLoanAmount1 = partialLoanAmountETH *
            uint256(INITIAL_EXCHANGE_RATE);
        vault.borrow(partialLoanAmount1);

        // set new rate
        priceFeed.modifyExchangeRate(320000000000);
        (, int256 exchangeRate, , , ) = priceFeed.latestRoundData();

        uint256 partialLoanAmount2 = (totalDepositETH * uint256(exchangeRate)) -
            (partialLoanAmountETH * uint256(INITIAL_EXCHANGE_RATE));

        vault.borrow(partialLoanAmount2);

        uint256 totalLoanAmount = partialLoanAmount1 + partialLoanAmount2;

        assertEq(vault.loans(address(this)), totalLoanAmount);
        assertEq(dai.balanceOf(address(this)), totalLoanAmount);
        assertEq(
            dai.balanceOf(address(vault)),
            INITIAL_VAULT_DAI_BALANCE - totalLoanAmount
        );
    }

    function testBorrowDepreciateETH() public {
        _setUpBalances();

        vault.deposit{value: 10 ether}();

        // set new rate
        priceFeed.modifyExchangeRate(280000000000);
        (, int256 exchangeRate, , , ) = priceFeed.latestRoundData();

        uint256 loanAmount = 10 * uint256(exchangeRate);
        vault.borrow(loanAmount);

        assertEq(vault.loans(address(this)), loanAmount);
        assertEq(dai.balanceOf(address(this)), loanAmount);
        assertEq(
            dai.balanceOf(address(vault)),
            INITIAL_VAULT_DAI_BALANCE - loanAmount
        );
    }

    function testBorrowMultipleDepreciateETH() public {
        _setUpBalances();

        uint256 totalDepositETH = 10;
        uint256 partialLoanAmountETH = 5;

        vault.deposit{value: 10 ether}();

        uint256 partialLoanAmount1 = partialLoanAmountETH *
            uint256(INITIAL_EXCHANGE_RATE);
        vault.borrow(partialLoanAmount1);

        // set new rate
        priceFeed.modifyExchangeRate(280000000000);
        (, int256 exchangeRate, , , ) = priceFeed.latestRoundData();

        uint256 partialLoanAmount2 = (totalDepositETH * uint256(exchangeRate)) -
            (partialLoanAmountETH * uint256(INITIAL_EXCHANGE_RATE));
        vault.borrow(partialLoanAmount2);

        uint256 totalLoanAmount = partialLoanAmount1 + partialLoanAmount2;

        assertEq(vault.loans(address(this)), totalLoanAmount);
        assertEq(dai.balanceOf(address(this)), totalLoanAmount);
        assertEq(
            dai.balanceOf(address(vault)),
            INITIAL_VAULT_DAI_BALANCE - totalLoanAmount
        );
    }

    function testBorrowFuzz(uint256 depositAmount) public {
        vm.assume(
            depositAmount <
                type(uint256).max / (1e18 * uint256(INITIAL_EXCHANGE_RATE))
        );
        uint256 depositETH = depositAmount * 1e18;
        uint256 daiMint = depositETH * uint256(INITIAL_EXCHANGE_RATE);

        vm.deal(address(this), depositETH);
        dai.mint(address(vault), daiMint);

        vault.deposit{value: depositETH}();

        uint256 loanAmount = depositAmount * uint256(INITIAL_EXCHANGE_RATE);
        vault.borrow(loanAmount);

        assertEq(vault.loans(address(this)), loanAmount);
        assertEq(dai.balanceOf(address(this)), loanAmount);
        assertEq(dai.balanceOf(address(vault)), daiMint - loanAmount);
    }

    function testBorrowPartialFuzz(uint256 depositAmount) public {
        vm.assume(
            depositAmount <
                type(uint256).max / (1e18 * uint256(INITIAL_EXCHANGE_RATE))
        );
        uint256 depositETH = depositAmount * 1e18;
        uint256 daiMint = depositETH * uint256(INITIAL_EXCHANGE_RATE);

        vm.deal(address(this), depositETH);
        dai.mint(address(vault), daiMint);

        vault.deposit{value: depositETH}();

        uint256 partialLoanAmount = (depositAmount *
            uint256(INITIAL_EXCHANGE_RATE)) >> 1;
        vault.borrow(partialLoanAmount);

        assertEq(vault.loans(address(this)), partialLoanAmount);
        assertEq(dai.balanceOf(address(this)), partialLoanAmount);
        assertEq(dai.balanceOf(address(vault)), daiMint - partialLoanAmount);
    }

    function testBorrowMultipleFuzz(uint256 depositAmount) public {
        vm.assume(
            depositAmount <
                type(uint256).max / (1e18 * uint256(INITIAL_EXCHANGE_RATE))
        );
        uint256 depositETH = depositAmount * 1e18;
        uint256 daiMint = depositETH * uint256(INITIAL_EXCHANGE_RATE);

        vm.deal(address(this), depositETH);
        dai.mint(address(vault), daiMint);

        vault.deposit{value: depositETH}();

        uint256 totalLoanAmount = depositAmount *
            uint256(INITIAL_EXCHANGE_RATE);
        uint256 partialLoanAmount = totalLoanAmount >> 1;

        vault.borrow(partialLoanAmount);
        vault.borrow(partialLoanAmount);

        assertEq(vault.loans(address(this)), totalLoanAmount);
        assertEq(dai.balanceOf(address(this)), totalLoanAmount);
        assertEq(dai.balanceOf(address(vault)), daiMint - totalLoanAmount);
    }

    function testBorrowInsufficientCollateralFuzz(uint256 depositAmount)
        public
    {
        vm.assume(
            depositAmount <
                type(uint256).max / (1e18 * uint256(INITIAL_EXCHANGE_RATE))
        );
        uint256 depositETH = depositAmount * 1e18;
        uint256 daiMint = depositETH * uint256(INITIAL_EXCHANGE_RATE);

        vm.deal(address(this), depositETH);
        dai.mint(address(vault), daiMint);

        vault.deposit{value: depositETH}();

        uint256 totalLoanAmount = depositAmount *
            uint256(INITIAL_EXCHANGE_RATE);
        uint256 partialLoanAmount = totalLoanAmount >> 1;

        vault.borrow(partialLoanAmount);

        vm.expectRevert(abi.encodeWithSignature("InsufficientCollateral()"));
        vault.borrow(partialLoanAmount + 1);

        assertEq(vault.loans(address(this)), partialLoanAmount);
        assertEq(dai.balanceOf(address(this)), partialLoanAmount);
        assertEq(dai.balanceOf(address(vault)), daiMint - partialLoanAmount);
    }

    function testWithdraw() public {
        _setUpBalances();

        vault.deposit{value: 10 ether}();

        vault.withdraw(10 ether);

        assertEq(vault.loans(address(this)), 0);
        assertEq(vault.deposits(address(this)), 0 ether);
        assertEq(dai.balanceOf(address(this)), 0);
        assertEq(dai.balanceOf(address(vault)), INITIAL_VAULT_DAI_BALANCE);
    }

    function testWithdrawPartial() public {
        _setUpBalances();

        vault.deposit{value: 10 ether}();

        vault.withdraw(5 ether);

        assertEq(vault.loans(address(this)), 0);
        assertEq(vault.deposits(address(this)), 5 ether);
        assertEq(dai.balanceOf(address(this)), 0);
        assertEq(dai.balanceOf(address(vault)), INITIAL_VAULT_DAI_BALANCE);
    }

    function testWithdrawMultiple() public {
        _setUpBalances();

        vault.deposit{value: 10 ether}();

        vault.withdraw(5 ether);
        vault.withdraw(5 ether);

        assertEq(vault.loans(address(this)), 0);
        assertEq(vault.deposits(address(this)), 0 ether);
        assertEq(dai.balanceOf(address(this)), 0);
        assertEq(dai.balanceOf(address(vault)), INITIAL_VAULT_DAI_BALANCE);
    }

    function testWithdrawInsufficientBalance() public {
        _setUpBalances();

        vault.deposit{value: 10 ether}();

        vm.expectRevert(abi.encodeWithSignature("InsufficientBalance()"));
        vault.withdraw(11 ether);

        assertEq(vault.loans(address(this)), 0);
        assertEq(vault.deposits(address(this)), 10 ether);
        assertEq(dai.balanceOf(address(this)), 0);
        assertEq(dai.balanceOf(address(vault)), INITIAL_VAULT_DAI_BALANCE);
    }

    function testWithdrawMultipleInsufficientBalance() public {
        _setUpBalances();

        vault.deposit{value: 10 ether}();

        vault.withdraw(5 ether);

        vm.expectRevert(abi.encodeWithSignature("InsufficientBalance()"));
        vault.withdraw(6 ether);

        assertEq(vault.loans(address(this)), 0);
        assertEq(vault.deposits(address(this)), 5 ether);
        assertEq(dai.balanceOf(address(this)), 0);
        assertEq(dai.balanceOf(address(vault)), INITIAL_VAULT_DAI_BALANCE);
    }

    function testWithdrawWithLoan() public {
        _setUpBalances();

        vault.deposit{value: 10 ether}();

        uint256 loanAmount = 5 * uint256(INITIAL_EXCHANGE_RATE);
        vault.borrow(loanAmount);

        vault.withdraw(5 ether);

        assertEq(vault.loans(address(this)), loanAmount);
        assertEq(vault.deposits(address(this)), 5 ether);
        assertEq(dai.balanceOf(address(this)), loanAmount);
        assertEq(
            dai.balanceOf(address(vault)),
            INITIAL_VAULT_DAI_BALANCE - loanAmount
        );
    }

    function testWithdrawWithMultipleLoans() public {
        _setUpBalances();

        vault.deposit{value: 10 ether}();

        uint256 loanAmount = 2 * uint256(INITIAL_EXCHANGE_RATE);
        vault.borrow(loanAmount);
        vault.borrow(loanAmount);

        vault.withdraw(6 ether);

        assertEq(vault.loans(address(this)), loanAmount * 2);
        assertEq(vault.deposits(address(this)), 4 ether);
        assertEq(dai.balanceOf(address(this)), loanAmount * 2);
        assertEq(
            dai.balanceOf(address(vault)),
            INITIAL_VAULT_DAI_BALANCE - loanAmount * 2
        );
    }

    function testWithdrawWithMultipleLoansAndInsufficientBalance() public {
        _setUpBalances();

        vault.deposit{value: 10 ether}();

        uint256 loanAmount = 2 * uint256(INITIAL_EXCHANGE_RATE);
        vault.borrow(loanAmount);
        vault.borrow(loanAmount);

        vm.expectRevert(abi.encodeWithSignature("InsufficientBalance()"));
        vault.withdraw(7 ether);

        assertEq(vault.loans(address(this)), loanAmount * 2);
        assertEq(vault.deposits(address(this)), 10 ether);
        assertEq(dai.balanceOf(address(this)), loanAmount * 2);
        assertEq(
            dai.balanceOf(address(vault)),
            INITIAL_VAULT_DAI_BALANCE - loanAmount * 2
        );
    }

    function testRepay() public {
        _setUpBalances();

        vault.deposit{value: 10 ether}();

        uint256 loanAmount = 5 * uint256(INITIAL_EXCHANGE_RATE);
        vault.borrow(loanAmount);

        dai.approve(address(vault), loanAmount);
        vault.repay(loanAmount);

        assertEq(vault.loans(address(this)), 0);
        assertEq(vault.deposits(address(this)), 10 ether);
        assertEq(dai.balanceOf(address(this)), 0);
        assertEq(dai.balanceOf(address(vault)), INITIAL_VAULT_DAI_BALANCE);
    }

    function testRepayPartial() public {
        _setUpBalances();

        vault.deposit{value: 10 ether}();

        uint256 loanAmount = 5 * uint256(INITIAL_EXCHANGE_RATE);
        vault.borrow(loanAmount);

        uint256 repayAmount = 3 * uint256(INITIAL_EXCHANGE_RATE);
        dai.approve(address(vault), repayAmount);
        vault.repay(repayAmount);

        assertEq(vault.loans(address(this)), loanAmount - repayAmount);
        assertEq(vault.deposits(address(this)), 10 ether);
        assertEq(dai.balanceOf(address(this)), loanAmount - repayAmount);
        assertEq(
            dai.balanceOf(address(vault)),
            INITIAL_VAULT_DAI_BALANCE - loanAmount + repayAmount
        );
    }

    function testRepayInvalidAmount() public {
        _setUpBalances();

        vault.deposit{value: 10 ether}();

        uint256 loanAmount = 5 * uint256(INITIAL_EXCHANGE_RATE);
        vault.borrow(loanAmount);

        vm.expectRevert(abi.encodeWithSignature("InvalidAmount()"));
        vault.repay(loanAmount + 1 ether);

        assertEq(vault.loans(address(this)), loanAmount);
        assertEq(vault.deposits(address(this)), 10 ether);
        assertEq(dai.balanceOf(address(this)), loanAmount);
        assertEq(
            dai.balanceOf(address(vault)),
            INITIAL_VAULT_DAI_BALANCE - loanAmount
        );
    }

    function testLiquidate() public {
        _setUpBalances();

        vault.deposit{value: 10 ether}();

        uint256 loanAmount = 5 * uint256(INITIAL_EXCHANGE_RATE);
        vault.borrow(loanAmount);

        priceFeed.modifyExchangeRate(10000000000);
        assertEq(
            vault.applyExchangeRate(vault.deposits(address(this))),
            100000000000
        );

        vm.prank(vaultOwner);
        vault.liquidate(address(this));

        assertEq(vault.loans(address(this)), 0);
        assertEq(vault.deposits(address(this)), 0 ether);
        assertEq(dai.balanceOf(address(this)), loanAmount);
        assertEq(
            dai.balanceOf(address(vault)),
            INITIAL_VAULT_DAI_BALANCE - loanAmount
        );
    }

    function testLiquidateUnauthorised() public {
        vm.expectRevert(abi.encodeWithSignature("Unauthorised()"));
        vault.liquidate(address(this));
    }

    function testLiquidateSafe() public {
        _setUpBalances();

        vault.deposit{value: 10 ether}();

        uint256 loanAmount = 5 * uint256(INITIAL_EXCHANGE_RATE);
        vault.borrow(loanAmount);

        vm.expectRevert(abi.encodeWithSignature("Safe()"));
        vm.prank(vaultOwner);
        vault.liquidate(address(this));

        assertEq(vault.loans(address(this)), loanAmount);
        assertEq(vault.deposits(address(this)), 10 ether);
        assertEq(dai.balanceOf(address(this)), loanAmount);
        assertEq(
            dai.balanceOf(address(vault)),
            INITIAL_VAULT_DAI_BALANCE - loanAmount
        );
    }

    receive() external payable {}
}
