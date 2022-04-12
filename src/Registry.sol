// SPDX-License-Identifier: MIT
pragma solidity >=0.8.12;

/// @notice Simple registry that registers a string name to an address.
/// @dev time period of 1 day is used to prevent spamming.
contract Registry {
    // ============== Custom Errors ==============

    error AlreadyClaimed();
    error EarlyClaim();
    error Unauthorised();

    // ============== Events ==============

    event NameClaimed(address indexed _claimer, string _name);
    event NameReleased(address indexed _releaser, string _name);

    // ============== Public State Variables ==============

    uint256 public constant CLAIM_PERIOD = 1 days;
    mapping(string => address) public names;
    mapping(address => uint256) public lastClaimedAt;

    // ============== Public FUnctions ==============

    function claim(string memory name) public payable {
        if (names[name] != address(0)) revert AlreadyClaimed();
        if (block.timestamp < lastClaimedAt[msg.sender] + CLAIM_PERIOD)
            revert EarlyClaim();

        lastClaimedAt[msg.sender] = block.timestamp;
        names[name] = msg.sender;
        emit NameClaimed(msg.sender, name);
    }

    function release(string memory name) public payable {
        if (names[name] != msg.sender) revert Unauthorised();

        names[name] = address(0);
        emit NameReleased(msg.sender, name);
    }
}
