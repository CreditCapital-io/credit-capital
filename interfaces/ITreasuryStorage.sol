// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

interface IPool {
    struct Pool {
        uint256 totalPooled; // total token pooled in the contract
    }
}

interface IUserPositions {
    struct UserPosition {
        uint256 totalAmount; // total value staked by user in given pool
        uint256 rewardDebt; // house fee (?)
        uint256 userLastWithdrawnStakeIndex; // track the last unlocked index for each user's position in a pool, so that withdrawal iteration is less expensive
        bool staticLock; // guarantees a users stake is locked, even after timelock expiration
        bool autocompounding; // this userposition enables auto compounding (Auto restaking the rewards)
    }
}

interface ITreasuryStorage {
    function deposit(
        address _user,
        address _token,
        uint256 _amount
    ) external;

    function updatePool(
        address _token,
        uint256 _amount
    ) external returns (IPool.Pool memory);

    function addUserPosition(
        address _token,
        address _user,
        uint256 _totalAmount
    ) external;

    function setUserPosition(
        address _token,
        address _user,
        uint256 _amount
    ) external;

    function setUserDebt(
        address _token,
        address _user
    ) external;

    function loan(
        address _token,
        address _user,
        uint256 _amount
    ) external;

    function withdraw(
        address _token,
        address _user,
        uint256 _amount
    ) external;

    function returnPrincipal(
        address _user,
        address _token,
        uint256 _principal
    ) external;

    function getTokenSupply(address _token) external returns (uint256);

    function getPool(address _token) external returns (IPool.Pool memory);

    function getUserPosition(address _token, address _user)
        external
        view
        returns (IUserPositions.UserPosition memory);

    function getUnlockedAmount(address _token, address _user)
        external
        view
        returns (uint256);

    function checkIfPoolExists(address _token) external returns (bool);

    function checkIfUserPositionExists(address _user, address _token)
        external
        returns (bool);
}
