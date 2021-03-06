//SPDX-License-Identifier: MIT
pragma solidity 0.8.11;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract VaultMock is AccessControl, Pausable {
    using SafeERC20 for IERC20;

    bytes32 public constant REWARDS = keccak256("REWARDS");

    uint256 timelock = 10 minutes; // 4 years, 4 months, 4 days ...

    struct Stake {
        uint256 amount; // quantity staked
        uint256 startTime; // stake creation timestamp
        uint256 timeLockEnd; // The point at which the (4 yr, 4 mo, 4 day) timelock ends for a stake, and thus the funds can be withdrawn.
        bool active; // true = stake in vault, false = user withdrawn stake
    }

    struct UserPosition {
        uint256 totalAmount; // total value staked by user in given pool
        uint256 rewardDebt; // house fee (?)
        uint256 userLastWithdrawnStakeIndex; // track the last unlocked index for each user's position in a pool, so that withdrawal iteration is less expensive
        bool staticLock; // guarantees a users stake is locked, even after timelock expiration
        bool autocompounding; // this userposition enables auto compounding (Auto restaking the rewards)
        Stake[] stakes; // list of user stakes in pool subject to timelock
    }

    // user position tracking
    mapping(address => mapping(address => UserPosition)) UserPositions; // account => (token => userposition)

    struct Pool {
        uint256 totalPooled; // total token pooled in the contract
        uint256 rewardsPerSecond; // rate at which CAPL is minted for this pool
        uint256 accCaplPerShare; // weighted CAPL share in pool
        uint256 lastRewardTime; // last time a claim was made
    }

    // pool tracking
    mapping(address => Pool) Pools; // token => pool

    uint256 CAPL_PRECISION = 1e18;

    event Deposit(address user, address token, uint256 amount);
    event Withdraw(address user, address token, uint256 amount);
    event WithdrawMATIC(address destination, uint256 amount);

    // TBD: Assume creation with one pool required (?)
    // TBD: Assume creation with one pool required (?)
    constructor(address _token, uint256 _rewardsPerSecond) {
        // RBAC
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        grantRole(REWARDS, msg.sender);
        grantRole(REWARDS, address(this));

        // create first pool
        addPool(_token, _rewardsPerSecond);
    }

    function updatePool(
        address _token,
        uint256 _accCaplPerShare,
        uint256 _lastRewardTime
    ) external returns (Pool memory) {
        Pools[_token].lastRewardTime = _lastRewardTime;
        Pools[_token].accCaplPerShare = _accCaplPerShare;

        return Pools[_token];
    }

    function addPoolPosition(address _token, uint256 _amount)
        public
        onlyRole(REWARDS)
    {
        Pools[_token].totalPooled += _amount;
    }

    function removePoolPosition(address _token, uint256 _amount)
        external
        onlyRole(REWARDS)
    {
        Pool storage pool = Pools[_token];
        require(pool.totalPooled >= _amount, "Pooled amount is not enough");
        pool.totalPooled -= _amount;
    }

    function withdraw(
        address _token,
        address _user,
        uint256 _amount,
        uint256 _newRewardDebt
    ) external whenNotPaused onlyRole(REWARDS) {
        require(_amount > 0, "Amount 0");

        UserPosition storage userPosition = UserPositions[_user][_token];

        require(
            userPosition.totalAmount >= _amount,
            "Withdrawn amount exceed the user balance"
        );

        // update userPosition
        userPosition.totalAmount -= _amount;
        userPosition.rewardDebt = _newRewardDebt;

        // reset the stakes to the default value related to the unlocked amount
        Stake[] storage stakes = UserPositions[_user][_token].stakes;
        for (
            uint256 i = 0;
            i <= userPosition.userLastWithdrawnStakeIndex;
            i++
        ) {
            // reset the stake to the default value - in this case 0
            delete stakes[i];
        }

        IERC20(_token).safeTransfer(_user, _amount);
        emit Withdraw(_user, _token, _amount);
    }

    function addStake(
        address _token,
        address _user,
        uint256 _amount
    ) external {
        // create user & stake data
        Stake memory stake = Stake({
            amount: _amount, // first stake
            startTime: block.timestamp,
            timeLockEnd: block.timestamp + timelock,
            active: true
        });

        UserPositions[_user][_token].stakes.push(stake);
    }

    function setStake(
        address _token,
        address _user,
        uint256 _amount,
        uint256 _stakeId
    ) external onlyRole(REWARDS) {
        Stake storage stake = UserPositions[_user][_token].stakes[_stakeId];
        stake.amount += _amount;
    }

    /*
        Read functions
    */
    function getPool(address _token) external view returns (Pool memory) {
        require(checkIfPoolExists(_token), "The pool does not exists.");

        return Pools[_token];
    }

    function checkIfPoolExists(address _token) public view returns (bool) {
        return Pools[_token].rewardsPerSecond > 0;
    }

    function getPendingRewards(address _token, address _user)
        external
        view
        returns (uint256 pending)
    {
        Pool memory pool = Pools[_token];
        UserPosition memory user = UserPositions[_user][_token];

        uint256 accCaplPerShare = pool.accCaplPerShare;
        uint256 tokenSupply = IERC20(_token).balanceOf(address(this));

        if (block.timestamp > pool.lastRewardTime && tokenSupply != 0) {
            uint256 blocks = block.timestamp - pool.lastRewardTime;
            uint256 caplReward = blocks * pool.rewardsPerSecond;
            accCaplPerShare += (caplReward * CAPL_PRECISION) / tokenSupply;
        }
        pending =
            ((user.totalAmount * accCaplPerShare) / CAPL_PRECISION) -
            user.rewardDebt;
    }

    /*  This function will check if a new stake needs to be created based on lockingThreshold.
        See readme for details.
    */
    function checkTimelockThreshold(Stake storage _lastStake)
        internal
        view
        returns (bool)
    {
        return _lastStake.timeLockEnd < block.timestamp;
    }

    function checkIfUserPositionExists(address _token, address _user)
        external
        view
        returns (bool)
    {
        return UserPositions[_user][_token].totalAmount > 0;
    }

    function getUserPosition(address _token, address _user)
        external
        view
        onlyRole(REWARDS)
        returns (UserPosition memory)
    {
        return UserPositions[_user][_token];
    }

    function getUnlockedAmount(address _token, address _user)
        external
        onlyRole(REWARDS)
        returns (uint256)
    {
        UserPosition storage userPosition = UserPositions[_user][_token];
        Stake[] memory stakes = UserPositions[_user][_token].stakes;

        uint256 unlockedAmount = 0;
        uint256 lastUnlockedIndex;

        for (
            uint256 i = userPosition.userLastWithdrawnStakeIndex;
            i < stakes.length;
            i++
        ) {
            if (stakes[i].timeLockEnd > block.timestamp) {
                break;
            }
            unlockedAmount += stakes[i].amount;
            lastUnlockedIndex = i;
        }

        userPosition.userLastWithdrawnStakeIndex = lastUnlockedIndex;

        return unlockedAmount;
    }

    function getLastStake(address _token, address _user)
        external
        view
        onlyRole(REWARDS)
        returns (Stake memory)
    {
        UserPosition memory userPosition = UserPositions[_user][_token];
        uint256 lastStakeKey = userPosition.stakes.length - 1;

        return UserPositions[_user][_token].stakes[lastStakeKey];
    }

    function getLastStakeKey(address _token, address _user)
        external
        view
        onlyRole(REWARDS)
        returns (uint256)
    {
        return UserPositions[_user][_token].stakes.length - 1;
    }

    function getTokenSupply(address _token) external view returns (uint256) {
        return IERC20(_token).balanceOf(address(this));
    }

    /*
        Admin functions
    */

    function addPool(address _token, uint256 _rewardsPerSecond)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(!checkIfPoolExists(_token), "This pool already exists.");

        Pool memory pool = Pool({
            totalPooled: 0,
            rewardsPerSecond: _rewardsPerSecond,
            accCaplPerShare: 0,
            lastRewardTime: block.timestamp
        });

        Pools[_token] = pool;
    }

    function setPool(
        address _token,
        uint256 _accCaplPerShare,
        uint256 _lastRewardTime
    ) external onlyRole(REWARDS) returns (Pool memory) {
        require(checkIfPoolExists(_token), "Pool does not exist");

        Pools[_token].accCaplPerShare = _accCaplPerShare;
        Pools[_token].lastRewardTime = _lastRewardTime;

        return Pools[_token];
    }

    function addUserPosition(
        address _token,
        address _user,
        uint256 _amount,
        uint256 _rewardDebt
    ) public onlyRole(REWARDS) {
        // add new stake
        Stake memory userStake = Stake({
            amount: _amount, // first stake
            startTime: block.timestamp,
            timeLockEnd: block.timestamp + timelock,
            active: true
        });

        UserPosition storage userPosition = UserPositions[_user][_token];

        userPosition.totalAmount = _amount;
        userPosition.rewardDebt = _rewardDebt;
        userPosition.userLastWithdrawnStakeIndex = 0;
        userPosition.staticLock = false;
        userPosition.autocompounding = true;
        userPosition.stakes.push(userStake);
    }

    function setUserPosition(
        address _token,
        address _user,
        uint256 _amount,
        uint256 _rewardDebt
    ) external onlyRole(REWARDS) {
        // create new userPosition
        UserPositions[_user][_token].totalAmount += _amount;
        UserPositions[_user][_token].rewardDebt = _rewardDebt;
    }

    function setUserDebt(
        address _token,
        address _user,
        uint256 rewardDebt
    ) external onlyRole(REWARDS) {
        UserPositions[_user][_token].rewardDebt = rewardDebt;
    }

    function withdrawToken(
        address _token,
        uint256 _amount,
        address _destination
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        Pool storage pool = Pools[_token];

        require(_amount > 0 && pool.totalPooled >= _amount);

        // withdraw the token to user wallet
        IERC20(_token).safeTransfer(_destination, _amount);

        // update the pooled amount
        pool.totalPooled -= _amount;
    }

    function withdrawMATIC() public payable onlyRole(DEFAULT_ADMIN_ROLE) {
        require(address(this).balance > 0, "no matic to withdraw");
        uint256 balance = address(this).balance;

        payable(msg.sender).transfer(balance);

        emit WithdrawMATIC(msg.sender, balance);
    }
}
