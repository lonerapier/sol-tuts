// SPDX-License-Identifier: MIT
pragma solidity >=0.8.12;

import {Vault1} from "../Vault1.sol";
import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";

contract TestVault1 is DSTestPlus {
    address public constant sampleAdd = address(0xabcd);

    MockERC20 public token;
    Vault1 public vault;

    function setUp() public {
        token = new MockERC20("Vault1", "VT1", 18);
        token.mint(address(this), 1e18);

        vault = new Vault1(address(token));
    }

    function testDeposit() public {
        token.approve(address(vault), 100);
        vault.deposit(100);

        assertEq(vault.balances(address(this)), 100);
        assertEq(token.balanceOf(address(vault)), 100);
    }

    function testDepositFuzz(uint256 amount) public {
        vm.assume(amount < 1e18);

        token.approve(address(vault), amount);
        vault.deposit(amount);

        assertEq(vault.balances(address(this)), amount);
        assertEq(token.balanceOf(address(vault)), amount);
    }

    function testWithdraw() public {
        token.approve(address(vault), 100);
        vault.deposit(100);

        vault.withdraw(100);

        assertEq(vault.balances(address(this)), 0);
        assertEq(token.balanceOf(address(vault)), 0);
    }

    function testWithdrawPartial() public {
        token.approve(address(vault), 100);
        vault.deposit(100);

        vault.withdraw(30);

        assertEq(vault.balances(address(this)), 70);
    }

    function testWithdrawFuzz(uint256 depositAmount, uint256 withdrawAmount)
        public
    {
        vm.assume(depositAmount < 1e18);
        vm.assume(withdrawAmount <= depositAmount);

        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);

        vault.withdraw(withdrawAmount);

        assertEq(vault.balances(address(this)), depositAmount - withdrawAmount);
    }
}
