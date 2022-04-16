// SPDX-License-Identifier: MIT
pragma solidity >=0.8.12;

import {DSTestPlus} from "@solmate/test/utils/DSTestPlus.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";

import {MultiCollateralVault} from "../MultiCollateralVault.sol";
import {Dai} from "../Dai.sol";
import {MockPriceFeed} from "../MockPriceFeed.sol";

import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";

contract TestMultiCollateralVault is DSTestPlus {
    address public constant vaultOwner = address(0xabcd);
    address public constant mockUser = address(0x1234);
    address public constant collateralManager = address(0x5678);
    address public constant liquidator = address(0x9012);

    uint256 public constant INITIAL_VAULT_DAI_BALANCE = 1e12 * 1e18;
    uint256 public constant INITIAL_USER_TOKEN_BALANCE = 1e3 * 1e18;

    uint256 public constant CHAIN_ID = 4;
    Dai public dai;
    address[] public users;
    address[] public tokens;
    address[] public priceFeeds;
    uint256[] public initialTokenPrices;
    MultiCollateralVault public vault;

    function setUp() public {
        users.push(address(this));
        users.push(mockUser);

        dai = new Dai(CHAIN_ID);
        tokens.push(address(new MockERC20("WETH", "weth", 18)));
        tokens.push(address(new MockERC20("WBTC", "wbtc", 18)));

        initialTokenPrices.push(3000 * 1e8);
        initialTokenPrices.push(40000 * 1e8);

        priceFeeds = new address[](tokens.length);
        priceFeeds[0] = address(
            new MockPriceFeed(int256(initialTokenPrices[0]), 8)
        );
        priceFeeds[1] = address(
            new MockPriceFeed(int256(initialTokenPrices[1]), 8)
        );

        hevm.prank(vaultOwner);
        vault = new MultiCollateralVault(
            vaultOwner,
            address(dai),
            liquidator,
            collateralManager
        );
    }

    function _setUpBalances() private {
        dai.mint(address(vault), INITIAL_VAULT_DAI_BALANCE);
        for (uint256 i; i < users.length; ++i) {
            for (uint256 j; j < tokens.length; ++j) {
                MockERC20(tokens[j]).mint(users[i], INITIAL_USER_TOKEN_BALANCE);

                hevm.prank(users[i]);
                MockERC20(tokens[j]).approve(
                    address(vault),
                    INITIAL_USER_TOKEN_BALANCE
                );
            }
        }
    }

    function _setUpInitialPriceFeeds() private {
        hevm.startPrank(collateralManager);
        uint256 len = tokens.length;
        for (uint256 i; i < len; ++i) {
            vault.addNewCollateral(tokens[i], priceFeeds[i]);
        }
        hevm.stopPrank();
    }

    function testAddNewCollateralToken() public {
        _setUpInitialPriceFeeds();

        for (uint256 i; i < tokens.length; ++i) {
            assertTrue(vault.activeCollateral(tokens[i]));
            assertEq(vault.tokenPriceFeeds(tokens[i]), priceFeeds[i]);
        }
    }

    function testApplyExchangeRate() public {
        _setUpInitialPriceFeeds();
        _setUpBalances();

        uint256 amount = 10 ether;

        assertEq(
            vault.applyExchangeRate(tokens[0], amount),
            (amount * initialTokenPrices[0]) / 1e8
        );
    }

    function testApplyExchangeRateMultiple() public {
        _setUpInitialPriceFeeds();
        _setUpBalances();

        uint256 amount = 10 ether;

        assertEq(
            vault.applyExchangeRate(tokens[0], amount),
            (amount * initialTokenPrices[0]) / 1e8
        );
        assertEq(
            vault.applyExchangeRate(tokens[1], amount),
            (amount * initialTokenPrices[1]) / 1e8
        );
    }

    function testTotalDepositPrices() public {
        _setUpInitialPriceFeeds();
        _setUpBalances();

        uint256 amount = 10 * 1e18;

        vault.deposit(tokens[0], amount);
        vault.deposit(tokens[1], amount);

        uint256 totalDepositPrices = ((initialTokenPrices[0] +
            initialTokenPrices[1]) * amount) / 1e8;

        assertEq(
            vault.getTotalDepositPrices(address(this)),
            totalDepositPrices
        );
    }

    function testTotalDepositPricesFuzz(uint256 _amount) public {
        _amount = bound(_amount, 1, INITIAL_USER_TOKEN_BALANCE);

        _setUpInitialPriceFeeds();
        _setUpBalances();

        vault.deposit(tokens[0], _amount);
        vault.deposit(tokens[1], _amount);

        uint256 totalDepositPrices = ((initialTokenPrices[0] +
            initialTokenPrices[1]) * _amount) / 1e8;

        assertEq(
            vault.getTotalDepositPrices(address(this)),
            totalDepositPrices
        );
    }

    function testTotalDepositPricesFuzz(uint256 _amount1, uint256 _amount2)
        public
    {
        _amount1 = bound(_amount1, 1, INITIAL_USER_TOKEN_BALANCE);
        _amount2 = bound(_amount2, 1, INITIAL_USER_TOKEN_BALANCE);

        _setUpInitialPriceFeeds();
        _setUpBalances();

        vault.deposit(tokens[0], _amount1);
        vault.deposit(tokens[1], _amount2);

        uint256 totalDepositPrices = ((initialTokenPrices[0] * _amount1) +
            (initialTokenPrices[1] * _amount2)) / 1e8;

        assertEq(
            vault.getTotalDepositPrices(address(this)),
            totalDepositPrices
        );
    }

    function testDeposits() public {
        _setUpInitialPriceFeeds();
        _setUpBalances();

        uint256 amount = 10 * 1e18;
        vault.deposit(tokens[0], amount);

        assertEq(vault.deposits(tokens[0], address(this)), amount);
        assertEq(
            MockERC20(tokens[0]).balanceOf(address(this)),
            INITIAL_USER_TOKEN_BALANCE - amount
        );
        assertEq(MockERC20(tokens[0]).balanceOf(address(vault)), amount);
    }

    function testDepositsMultiple() public {
        _setUpInitialPriceFeeds();
        _setUpBalances();

        uint256 amount = 10 * 1e18;

        vault.deposit(tokens[0], amount);
        vault.deposit(tokens[1], amount);

        assertEq(vault.deposits(tokens[0], address(this)), amount);
        assertEq(vault.deposits(tokens[1], address(this)), amount);
        assertEq(
            MockERC20(tokens[0]).balanceOf(address(this)),
            INITIAL_USER_TOKEN_BALANCE - amount
        );
        assertEq(
            MockERC20(tokens[1]).balanceOf(address(this)),
            INITIAL_USER_TOKEN_BALANCE - amount
        );
        assertEq(MockERC20(tokens[0]).balanceOf(address(vault)), amount);
        assertEq(MockERC20(tokens[1]).balanceOf(address(vault)), amount);
    }

    function testDepositsMultipleAddresses() public {
        _setUpInitialPriceFeeds();
        _setUpBalances();

        uint256 amount = 10 * 1e18;

        for (uint256 i; i < users.length; ++i) {
            hevm.startPrank(users[i]);
            vault.deposit(tokens[0], amount);
            vault.deposit(tokens[1], amount);
            hevm.stopPrank();

            assertEq(vault.deposits(tokens[0], users[i]), amount);
            assertEq(vault.deposits(tokens[1], users[i]), amount);
        }
    }

    function testDepositInvalidCollateral() public {
        _setUpBalances();

        uint256 amount = 10 * 1e18;

        hevm.expectRevert(abi.encodeWithSignature("InvalidCollateral()"));
        vault.deposit(tokens[0], amount);
    }

    function testDepositInvalidAmount() public {
        _setUpInitialPriceFeeds();

        hevm.expectRevert(abi.encodeWithSignature("InvalidAmount()"));
        vault.deposit(tokens[0], 0);
    }

    function testDepositFuzz(uint256 _amount) public {
        _amount = bound(_amount, 1, INITIAL_USER_TOKEN_BALANCE);

        _setUpInitialPriceFeeds();
        _setUpBalances();

        vault.deposit(tokens[0], _amount);
        vault.deposit(tokens[1], _amount);

        assertEq(vault.deposits(tokens[0], address(this)), _amount);
        assertEq(vault.deposits(tokens[1], address(this)), _amount);
    }

    function testDepositsMultipleAddressSameAmountFuzz(uint256 _amount) public {
        _amount = bound(_amount, 1, INITIAL_USER_TOKEN_BALANCE);

        _setUpInitialPriceFeeds();
        _setUpBalances();

        for (uint256 i; i < users.length; ++i) {
            hevm.startPrank(users[i]);
            vault.deposit(tokens[0], _amount);
            vault.deposit(tokens[1], _amount);
            hevm.stopPrank();

            assertEq(vault.deposits(tokens[0], users[i]), _amount);
            assertEq(vault.deposits(tokens[1], users[i]), _amount);
        }
    }

    function testDepositsMultipleAddressDifferentAmountFuzz(
        uint256 _amount1,
        uint256 _amount2
    ) public {
        _amount1 = bound(_amount1, 1, INITIAL_USER_TOKEN_BALANCE);
        _amount2 = bound(_amount2, 1, INITIAL_USER_TOKEN_BALANCE);

        _setUpInitialPriceFeeds();
        _setUpBalances();

        for (uint256 i; i < users.length; ++i) {
            hevm.startPrank(users[i]);
            vault.deposit(tokens[0], _amount1);
            vault.deposit(tokens[1], _amount2);
            hevm.stopPrank();

            assertEq(vault.deposits(tokens[0], users[i]), _amount1);
            assertEq(vault.deposits(tokens[1], users[i]), _amount2);
        }
    }

    function testDepositInvalidCollateralFuzz(address _token) public {
        hevm.assume(_token != tokens[0]);
        hevm.assume(_token != tokens[1]);

        _setUpInitialPriceFeeds();

        hevm.expectRevert(abi.encodeWithSignature("InvalidCollateral()"));
        vault.deposit(_token, 10 * 1e18);
    }

    function testBorrow() public {
        _setUpInitialPriceFeeds();
        _setUpBalances();

        uint256 amount = 10 * 1e18;
        vault.deposit(tokens[0], amount);

        uint256 loanAmount = vault.applyExchangeRate(tokens[0], amount);
        vault.borrow(loanAmount);

        assertEq(vault.loans(address(this)), loanAmount);
        assertEq(dai.balanceOf(address(this)), loanAmount);
        assertEq(
            dai.balanceOf(address(vault)),
            INITIAL_VAULT_DAI_BALANCE - loanAmount
        );
    }

    function testBorrowPartial() public {
        _setUpInitialPriceFeeds();
        _setUpBalances();

        uint256 amount = 10 * 1e18;
        vault.deposit(tokens[0], amount);

        uint256 partialLoanAmount = vault.applyExchangeRate(
            tokens[0],
            amount
        ) >> 1;
        vault.borrow(partialLoanAmount);

        assertEq(vault.loans(address(this)), partialLoanAmount);
        assertEq(dai.balanceOf(address(this)), partialLoanAmount);
        assertEq(
            dai.balanceOf(address(vault)),
            INITIAL_VAULT_DAI_BALANCE - partialLoanAmount
        );
    }

    function testBorrowMultiple() public {
        _setUpInitialPriceFeeds();
        _setUpBalances();

        uint256 amount = 10 * 1e18;
        vault.deposit(tokens[0], amount);
        vault.deposit(tokens[1], amount);

        uint256 loanAmount = vault.getTotalDepositPrices(address(this));

        vault.borrow(loanAmount);

        assertEq(vault.loans(address(this)), loanAmount);
        assertEq(dai.balanceOf(address(this)), loanAmount);
        assertEq(
            dai.balanceOf(address(vault)),
            INITIAL_VAULT_DAI_BALANCE - loanAmount
        );
    }

    function testBorrowMultiplePartial() public {
        _setUpInitialPriceFeeds();
        _setUpBalances();

        uint256 amount = 10 * 1e18;
        vault.deposit(tokens[0], amount);
        vault.deposit(tokens[1], amount);

        uint256 partialLoanAmount = vault.getTotalDepositPrices(
            address(this)
        ) >> 1;

        vault.borrow(partialLoanAmount);

        assertEq(vault.loans(address(this)), partialLoanAmount);
        assertEq(dai.balanceOf(address(this)), partialLoanAmount);
        assertEq(
            dai.balanceOf(address(vault)),
            INITIAL_VAULT_DAI_BALANCE - partialLoanAmount
        );
    }

    function testBorrowInsufficientCollateral() public {
        _setUpInitialPriceFeeds();
        _setUpBalances();

        uint256 amount = 10 * 1e18;
        vault.deposit(tokens[0], amount);

        uint256 loanAmount = vault.applyExchangeRate(tokens[0], amount);
        hevm.expectRevert(abi.encodeWithSignature("InsufficientCollateral()"));
        vault.borrow(loanAmount + 1);
    }

    function testBorrowAppreciateToken() public {
        _setUpInitialPriceFeeds();
        _setUpBalances();

        uint256 amount = 10 * 1e18;
        vault.deposit(tokens[0], amount);

        MockPriceFeed(priceFeeds[0]).modifyExchangeRate(3200 * 1e8);

        uint256 loanAmount = vault.applyExchangeRate(tokens[0], amount);
        vault.borrow(loanAmount);

        assertEq(vault.loans(address(this)), loanAmount);
        assertEq(dai.balanceOf(address(this)), loanAmount);
        assertEq(
            dai.balanceOf(address(vault)),
            INITIAL_VAULT_DAI_BALANCE - loanAmount
        );
    }

    function testBorrowMultipleAppreciateToken() public {
        _setUpInitialPriceFeeds();
        _setUpBalances();

        uint256 amount = 10 * 1e18;
        vault.deposit(tokens[0], amount);
        vault.deposit(tokens[1], amount);

        MockPriceFeed(priceFeeds[0]).modifyExchangeRate(3200 * 1e8);
        MockPriceFeed(priceFeeds[1]).modifyExchangeRate(42000 * 1e8);

        uint256 loanAmount = vault.getTotalDepositPrices(address(this));
        vault.borrow(loanAmount);

        assertEq(vault.loans(address(this)), loanAmount);
        assertEq(dai.balanceOf(address(this)), loanAmount);
        assertEq(
            dai.balanceOf(address(vault)),
            INITIAL_VAULT_DAI_BALANCE - loanAmount
        );
    }

    function testBorrowMultipleAppreciateTokenPartial() public {
        _setUpInitialPriceFeeds();
        _setUpBalances();

        uint256 amount = 10 * 1e18;
        vault.deposit(tokens[0], amount);
        vault.deposit(tokens[1], amount);

        uint256 loanAmount = vault.getTotalDepositPrices(address(this));
        uint256 partialLoanAmount = loanAmount >> 1;

        vault.borrow(partialLoanAmount);

        // Appreciate token prices
        MockPriceFeed(priceFeeds[0]).modifyExchangeRate(3200 * 1e8);
        MockPriceFeed(priceFeeds[1]).modifyExchangeRate(42000 * 1e8);

        uint256 newLoanAmount = vault.getTotalDepositPrices(address(this));
        vault.borrow(newLoanAmount - partialLoanAmount);

        assertEq(vault.loans(address(this)), newLoanAmount);
        assertEq(dai.balanceOf(address(this)), newLoanAmount);
        assertEq(
            dai.balanceOf(address(vault)),
            INITIAL_VAULT_DAI_BALANCE - newLoanAmount
        );
    }

    function testBorrowDepreciateToken() public {
        _setUpInitialPriceFeeds();
        _setUpBalances();

        uint256 amount = 10 * 1e18;
        vault.deposit(tokens[0], amount);

        MockPriceFeed(priceFeeds[0]).modifyExchangeRate(1200 * 1e8);

        uint256 newLoanAmount = vault.applyExchangeRate(tokens[0], amount);
        vault.borrow(newLoanAmount);

        assertEq(vault.loans(address(this)), newLoanAmount);
        assertEq(dai.balanceOf(address(this)), newLoanAmount);
        assertEq(
            dai.balanceOf(address(vault)),
            INITIAL_VAULT_DAI_BALANCE - newLoanAmount
        );
    }

    function testBorrowMultipleDepreciateToken() public {
        _setUpInitialPriceFeeds();
        _setUpBalances();

        uint256 amount = 10 * 1e18;
        vault.deposit(tokens[0], amount);
        vault.deposit(tokens[1], amount);

        MockPriceFeed(priceFeeds[0]).modifyExchangeRate(1200 * 1e8);
        MockPriceFeed(priceFeeds[1]).modifyExchangeRate(1200 * 1e8);

        uint256 loanAmount = vault.getTotalDepositPrices(address(this));
        vault.borrow(loanAmount);

        assertEq(vault.loans(address(this)), loanAmount);
        assertEq(dai.balanceOf(address(this)), loanAmount);
        assertEq(
            dai.balanceOf(address(vault)),
            INITIAL_VAULT_DAI_BALANCE - loanAmount
        );
    }

    function testBorrowMultipleDepreciateTokenPartial() public {
        _setUpInitialPriceFeeds();
        _setUpBalances();

        uint256 amount = 10 * 1e18;
        vault.deposit(tokens[0], amount);
        vault.deposit(tokens[1], amount);

        uint256 loanAmount = vault.getTotalDepositPrices(address(this));
        uint256 partialLoanAmount = loanAmount >> 1;

        vault.borrow(partialLoanAmount);

        // Depreciate token prices
        MockPriceFeed(priceFeeds[0]).modifyExchangeRate(1500 * 1e8);
        MockPriceFeed(priceFeeds[1]).modifyExchangeRate(20000 * 1e8);

        uint256 newLoanAmount = vault.getTotalDepositPrices(address(this));
        vault.borrow(newLoanAmount - partialLoanAmount);

        assertEq(vault.loans(address(this)), newLoanAmount);
        assertEq(dai.balanceOf(address(this)), newLoanAmount);
        assertEq(
            dai.balanceOf(address(vault)),
            INITIAL_VAULT_DAI_BALANCE - newLoanAmount
        );
    }

    function testBorrowMultipleDepreciateTokenPartialUnderflow() public {
        _setUpInitialPriceFeeds();
        _setUpBalances();

        uint256 amount = 10 * 1e18;
        vault.deposit(tokens[0], amount);
        vault.deposit(tokens[1], amount);

        uint256 loanAmount = vault.getTotalDepositPrices(address(this));
        uint256 partialLoanAmount = loanAmount >> 1;

        vault.borrow(partialLoanAmount);

        // Depreciate token prices
        MockPriceFeed(priceFeeds[0]).modifyExchangeRate(1500 * 1e8);
        MockPriceFeed(priceFeeds[1]).modifyExchangeRate(1500 * 1e8);

        uint256 newLoanAmount = vault.getTotalDepositPrices(address(this));

        hevm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        vault.borrow(newLoanAmount - partialLoanAmount);

        assertEq(vault.loans(address(this)), partialLoanAmount);
        assertEq(dai.balanceOf(address(this)), partialLoanAmount);
        assertEq(
            dai.balanceOf(address(vault)),
            INITIAL_VAULT_DAI_BALANCE - partialLoanAmount
        );
    }

    function testBorrowFuzz(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, 1, INITIAL_USER_TOKEN_BALANCE);

        _setUpInitialPriceFeeds();
        _setUpBalances();

        vault.deposit(tokens[0], depositAmount);

        uint256 loanAmount = vault.getTotalDepositPrices(address(this));
        vault.borrow(loanAmount);

        assertEq(vault.loans(address(this)), loanAmount);
        assertEq(dai.balanceOf(address(this)), loanAmount);
        assertEq(
            dai.balanceOf(address(vault)),
            INITIAL_VAULT_DAI_BALANCE - loanAmount
        );
    }

    function testBorrowFuzzMultiple(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, 1, INITIAL_USER_TOKEN_BALANCE);

        _setUpInitialPriceFeeds();
        _setUpBalances();

        vault.deposit(tokens[0], depositAmount);
        vault.deposit(tokens[1], depositAmount);

        uint256 loanAmount = vault.getTotalDepositPrices(address(this));
        vault.borrow(loanAmount);

        assertEq(vault.loans(address(this)), loanAmount);
        assertEq(dai.balanceOf(address(this)), loanAmount);
        assertEq(
            dai.balanceOf(address(vault)),
            INITIAL_VAULT_DAI_BALANCE - loanAmount
        );
    }

    function testBorrowFuzzMultiplePartial(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, 1, INITIAL_USER_TOKEN_BALANCE);

        _setUpInitialPriceFeeds();
        _setUpBalances();

        vault.deposit(tokens[0], depositAmount);
        vault.deposit(tokens[1], depositAmount);

        uint256 partialLoanAmount = vault.getTotalDepositPrices(
            address(this)
        ) >> 1;

        vault.borrow(partialLoanAmount);

        assertEq(vault.loans(address(this)), partialLoanAmount);
        assertEq(dai.balanceOf(address(this)), partialLoanAmount);
        assertEq(
            dai.balanceOf(address(vault)),
            INITIAL_VAULT_DAI_BALANCE - partialLoanAmount
        );
    }

    function testBorrowFuzzMultipleToken(uint256 amount1, uint256 amount2)
        public
    {
        amount1 = bound(amount1, 1, INITIAL_USER_TOKEN_BALANCE);
        amount2 = bound(amount2, 1, INITIAL_USER_TOKEN_BALANCE);

        _setUpInitialPriceFeeds();
        _setUpBalances();

        vault.deposit(tokens[0], amount1);
        vault.deposit(tokens[1], amount2);

        uint256 loanAmount = vault.getTotalDepositPrices(address(this));
        vault.borrow(loanAmount);

        assertEq(vault.loans(address(this)), loanAmount);
        assertEq(dai.balanceOf(address(this)), loanAmount);
        assertEq(
            dai.balanceOf(address(vault)),
            INITIAL_VAULT_DAI_BALANCE - loanAmount
        );
    }

    function testBorrowFuzzMultipleTokenPartial(
        uint256 amount1,
        uint256 amount2
    ) public {
        amount1 = bound(amount1, 1, INITIAL_USER_TOKEN_BALANCE);
        amount2 = bound(amount2, 1, INITIAL_USER_TOKEN_BALANCE);

        _setUpInitialPriceFeeds();
        _setUpBalances();

        vault.deposit(tokens[0], amount1);
        vault.deposit(tokens[1], amount2);

        uint256 partialLoanAmount = vault.getTotalDepositPrices(
            address(this)
        ) >> 1;

        vault.borrow(partialLoanAmount);

        assertEq(vault.loans(address(this)), partialLoanAmount);
        assertEq(dai.balanceOf(address(this)), partialLoanAmount);
        assertEq(
            dai.balanceOf(address(vault)),
            INITIAL_VAULT_DAI_BALANCE - partialLoanAmount
        );
    }

    function testBorrowFuzzMultipleTokenPartialUnderflow(
        uint256 amount1,
        uint256 amount2
    ) public {
        amount1 = bound(amount1, 1, INITIAL_USER_TOKEN_BALANCE);
        amount2 = bound(amount2, 1, INITIAL_USER_TOKEN_BALANCE);

        _setUpInitialPriceFeeds();
        _setUpBalances();

        vault.deposit(tokens[0], amount1);
        vault.deposit(tokens[1], amount2);

        uint256 partialLoanAmount = vault.getTotalDepositPrices(
            address(this)
        ) >> 1;

        vault.borrow(partialLoanAmount);

        // Depreciate token prices
        MockPriceFeed(priceFeeds[0]).modifyExchangeRate(1500 * 1e8);
        MockPriceFeed(priceFeeds[1]).modifyExchangeRate(1500 * 1e8);

        uint256 newLoanAmount = vault.getTotalDepositPrices(address(this));

        hevm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        vault.borrow(newLoanAmount - partialLoanAmount);

        assertEq(vault.loans(address(this)), partialLoanAmount);
        assertEq(dai.balanceOf(address(this)), partialLoanAmount);
        assertEq(
            dai.balanceOf(address(vault)),
            INITIAL_VAULT_DAI_BALANCE - partialLoanAmount
        );
    }
}
