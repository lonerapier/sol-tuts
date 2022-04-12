// SPDX-License-Identifier: MIT
pragma solidity >=0.8.12;

interface IERC20 {
    function transfer(address _to, uint256 _value) external;

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external;
}
