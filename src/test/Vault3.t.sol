// SPDX-License-Identifier: MIT
pragma solidity >=0.8.12;

import {Vault3} from "../Vault3.sol";
import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";

contract TestVault3 is DSTestPlus {
    address public constant sampleAdd = address(0xabcd);

    MockERC20 public token;
    Vault3 public vault;

    function setUp() public {
        token = new MockERC20("Vault3", "VT3", 18);
        token.mint(address(this), 1e18);

        vault = new Vault3(address(token), uint256(2e18));
    }

    function testSetExchangeRate() public {
        assertEq(vault.exchangeRate(), 2e18);

        vault.setExchangeRate(1e18);

        assertEq(vault.exchangeRate(), 1e18);
    }

    function testSetExchangeRateZero() public {
        vm.expectRevert(abi.encodeWithSignature("InvalidExchangeRate()"));
        vault.setExchangeRate(0);
    }

    function testSetExchangeRateUnauthorised() public {
        vm.prank(sampleAdd);
        vm.expectRevert(abi.encodeWithSignature("Unauthorised()"));
        vault.setExchangeRate(1e18);
    }

    function testSetExchangeRateFuzz(uint256 rate) public {
        vm.assume(rate != 0);

        vault.setExchangeRate(rate);

        assertEq(vault.exchangeRate(), rate);
    }

    function testDeposit() public {
        token.approve(address(vault), 100);
        uint256 liquidity = vault.deposit(100);

        assertEq(vault.balanceOf(address(this)), liquidity);
        assertEq(token.balanceOf(address(vault)), 100);
    }

    function testDepositFuzz(uint256 amount) public {
        vm.assume(amount < 1e18);

        token.approve(address(vault), amount);
        uint256 liquidity = vault.deposit(amount);

        assertEq(vault.balanceOf(address(this)), liquidity);
        assertEq(token.balanceOf(address(vault)), amount);
    }

    function testWithdraw() public {
        token.approve(address(vault), 100);
        vault.deposit(100);

        vault.withdraw(100);

        assertEq(vault.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(vault)), 0);
    }

    function testWithdrawPartial() public {
        token.approve(address(vault), 100);
        uint256 mintedLiquidity = vault.deposit(100);

        uint256 burnedLiquidity = vault.withdraw(30);

        assertEq(
            vault.balanceOf(address(this)),
            mintedLiquidity - burnedLiquidity
        );
    }

    function testWithdrawFuzz(uint256 depositAmount, uint256 withdrawAmount)
        public
    {
        vm.assume(depositAmount < 1e18);
        vm.assume(withdrawAmount <= depositAmount);

        token.approve(address(vault), depositAmount);
        uint256 mintedLiquidity = vault.deposit(depositAmount);

        uint256 burnedLiquidity = vault.withdraw(withdrawAmount);

        assertEq(
            vault.balanceOf(address(this)),
            mintedLiquidity - burnedLiquidity
        );
    }
}
