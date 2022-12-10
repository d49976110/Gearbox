// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../tokens/DieselToken.sol";
import "../interfaces/IInterestRateModel.sol";
import "../interfaces/ICreditManager.sol";
import "../libraries/helpers/Constants.sol";
import "hardhat/console.sol";

contract PoolService is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public underlyingToken;
    address public dieselToken;

    // last update liquidity
    uint256 public _expectedLiquidityLU;

    uint256 public _timestampLU;

    uint256 public totalBorrowed;
    uint256 public borrowAPY_RAY;
    uint256 public _cumulativeIndex_RAY;

    mapping(address => bool) public creditManagersCanBorrow;
    mapping(address => bool) public creditManagersCanRepay;
    address[] public creditManagers;

    address public treasuryAddress;

    IInterestRateModel public interestRateModel;

    uint256 public withdrawFee;

    event AddLiquidity(
        address indexed sender,
        address indexed onBehalfOf,
        uint256 amount,
        uint256 referralCode
    );

    // Emits each time when LP removes liquidity to the pool
    event RemoveLiquidity(
        address indexed sender,
        address indexed to,
        uint256 amount
    );

    // Emits each time when Credit Manager borrows money from pool
    event Borrow(
        address indexed creditManager,
        address indexed creditAccount,
        uint256 amount
    );

    // Emits each time when Credit Manager repays money from pool
    event Repay(
        address indexed creditManager,
        uint256 borrowedAmount,
        uint256 profit,
        uint256 loss
    );

    event NewInterestRateModel(address indexed newInterestRateModel);
    event NewWithdrawFee(uint256 fee);
    event NewCreditManagerConnected(address indexed creditManager);
    event UncoveredLoss(address indexed creditManager, uint256 loss);

    // ! need to deploy diesel token address and interest model first

    ///@param _underlyingToken put uni token : 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984
    constructor(
        address _treasuryAddress,
        address _underlyingToken,
        address _dieselAddress,
        address _interestRateModelAddress
    ) {
        require(
            _underlyingToken != address(0) &&
                _dieselAddress != address(0) &&
                _interestRateModelAddress != address(0),
            "ZERO_ADDRESS_IS_NOT_ALLOWED"
        );

        underlyingToken = _underlyingToken;
        dieselToken = _dieselAddress;
        treasuryAddress = _treasuryAddress;

        _cumulativeIndex_RAY = Constants.RAY;

        _updateInterestRateModel(_interestRateModelAddress);
    }

    // Add tokens to pool to get LP
    function addLiquidity(
        uint256 amount,
        address onBehalfOf,
        uint256 referralCode
    ) external whenNotPaused nonReentrant {
        require(onBehalfOf != address(0), "ZERO_ADDRESS_IS_NOT_ALLOWED");

        uint256 balanceBefore = IERC20(underlyingToken).balanceOf(
            address(this)
        );

        IERC20(underlyingToken).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );

        amount =
            IERC20(underlyingToken).balanceOf(address(this)) -
            balanceBefore;

        DieselToken(dieselToken).mint(onBehalfOf, toDiesel(amount));
        _expectedLiquidityLU = _expectedLiquidityLU + amount;
        _updateBorrowRate(0);

        emit AddLiquidity(msg.sender, onBehalfOf, amount, referralCode);
    }

    // Remove LP from pool to get back tokens
    function removeLiquidity(uint256 amount, address to)
        external
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        require(to != address(0), "ZERO_ADDRESS_IS_NOT_ALLOWED");

        uint256 underlyingTokensAmount = fromDiesel(amount);

        uint256 amountTreasury = (underlyingTokensAmount * withdrawFee) / 10000;
        uint256 amountSent = underlyingTokensAmount - amountTreasury;

        IERC20(underlyingToken).safeTransfer(to, amountSent);

        if (amountTreasury > 0) {
            IERC20(underlyingToken).safeTransfer(
                treasuryAddress,
                amountTreasury
            );
        }

        DieselToken(dieselToken).burn(msg.sender, amount);

        _expectedLiquidityLU = _expectedLiquidityLU - underlyingTokensAmount;
        _updateBorrowRate(0);

        emit RemoveLiquidity(msg.sender, to, amount);

        return amountSent;
    }

    // Lend tokens to the credit account
    function lendCreditAccount(uint256 borrowedAmount, address creditAccount)
        external
        whenNotPaused
    {
        require(
            creditManagersCanBorrow[msg.sender],
            "POOL_CONNECTED_CREDIT_MANAGERS_ONLY"
        );

        // Transfer funds to user credit account
        IERC20(underlyingToken).safeTransfer(creditAccount, borrowedAmount);

        // Update borrow Rate
        _updateBorrowRate(0);

        // Increase total borrowed amount
        totalBorrowed = totalBorrowed + borrowedAmount;

        emit Borrow(msg.sender, creditAccount, borrowedAmount);
    }

    // It's called after credit account funds transfer back to pool and updates corretly parameters.
    function repayCreditAccount(
        uint256 borrowedAmount,
        uint256 profit,
        uint256 loss
    ) external whenNotPaused {
        require(
            creditManagersCanRepay[msg.sender],
            "POOL_CONNECTED_CREDIT_MANAGERS_ONLY"
        );

        // ? why if there is any loss, the treasure address should pay for it
        // For fee surplus we mint tokens for treasury
        if (profit > 0) {
            DieselToken(dieselToken).mint(treasuryAddress, toDiesel(profit));
            _expectedLiquidityLU = _expectedLiquidityLU + profit;
        }
        // If returned money < borrowed amount + interest accrued
        // it tries to compensate loss by burning diesel (LP) tokens
        // from treasury fund
        else {
            uint256 amountToBurn = toDiesel(loss);

            uint256 treasuryBalance = DieselToken(dieselToken).balanceOf(
                treasuryAddress
            );

            if (treasuryBalance < amountToBurn) {
                amountToBurn = treasuryBalance;
                emit UncoveredLoss(
                    msg.sender,
                    loss - fromDiesel(treasuryBalance)
                );
            }

            // If treasury has enough funds, it just burns needed amount to keep diesel rate on the same level
            DieselToken(dieselToken).burn(treasuryAddress, amountToBurn);
        }

        // Update available liquidity
        _updateBorrowRate(loss);

        // Reduce total borrowed. Should be after _updateBorrowRate() for correct calculations
        totalBorrowed = totalBorrowed - borrowedAmount;

        emit Repay(msg.sender, borrowedAmount, profit, loss);
    }

    function connectCreditManager(address _creditManager) external onlyOwner {
        require(
            address(this) == ICreditManager(_creditManager).poolService(),
            "POOL_INCOMPATIBLE_CREDIT_ACCOUNT_MANAGER"
        );

        require(
            !creditManagersCanRepay[_creditManager],
            "POOL_CANT_ADD_CREDIT_MANAGER_TWICE"
        );

        creditManagersCanBorrow[_creditManager] = true;
        creditManagersCanRepay[_creditManager] = true;
        creditManagers.push(_creditManager);
        emit NewCreditManagerConnected(_creditManager);
    }

    function expectedLiquidity() public view returns (uint256) {
        // timeDifference = blockTime - previous timeStamp
        uint256 timeDifference = block.timestamp - _timestampLU;

        //                                    currentBorrowRate * timeDifference
        //  interestAccrued = totalBorrow *  ------------------------------------
        //                                             SECONDS_PER_YEAR
        //

        uint256 interestAccrued = (totalBorrowed *
            borrowAPY_RAY *
            timeDifference) / (Constants.RAY * Constants.SECONDS_PER_YEAR);

        return _expectedLiquidityLU + interestAccrued;
    }

    function updateInterestRateModel(address _interestRateModel)
        public
        onlyOwner
    {
        _updateInterestRateModel(_interestRateModel);
    }

    function setWithdrawFee(uint256 fee) public onlyOwner {
        require(
            fee < Constants.MAX_WITHDRAW_FEE,
            "POOL_INCORRECT_WITHDRAW_FEE"
        );
        withdrawFee = fee;
        emit NewWithdrawFee(fee);
    }

    function availableLiquidity() public view returns (uint256) {
        return IERC20(underlyingToken).balanceOf(address(this));
    }

    // amount / dieselRate
    // like compound exchange rate
    function toDiesel(uint256 amount) public view returns (uint256) {
        return (amount * Constants.RAY) / getDieselRate_RAY();
    }

    /// @dev Converts amount from diesel tokens to undelying token
    /// @param amount Amount in diesel tokens to be converted to diesel tokens
    function fromDiesel(uint256 amount) public view returns (uint256) {
        return (amount * getDieselRate_RAY()) / Constants.RAY;
    }

    // rate = expected liquidity / diesel tokens supply
    // expected liquidity will increase by time because expected liquidity = _expectedLiquidityLU + interestAccrued
    function getDieselRate_RAY() public view returns (uint256) {
        uint256 dieselSupply = IERC20(dieselToken).totalSupply();

        if (dieselSupply == 0) return Constants.RAY;

        return (expectedLiquidity() * Constants.RAY) / dieselSupply;
    }

    // credit manager _calcClosePaymentsPure need this
    function calcLinearCumulative_RAY() public view returns (uint256) {
        uint256 timeDifference = block.timestamp - uint256(_timestampLU);

        return
            calcLinearIndex_RAY(
                _cumulativeIndex_RAY,
                borrowAPY_RAY,
                timeDifference
            );
    }

    function calcLinearIndex_RAY(
        uint256 cumulativeIndex_RAY,
        uint256 currentBorrowRate_RAY,
        uint256 timeDifference
    ) public view returns (uint256) {
        //                                    /     currentBorrowRate * timeDifference \
        //  newCumIndex  = currentCumIndex * | 1 + ------------------------------------ |
        //                                    \              SECONDS_PER_YEAR          /
        //
        return
            (cumulativeIndex_RAY *
                (Constants.RAY +
                    ((currentBorrowRate_RAY * timeDifference) /
                        Constants.SECONDS_PER_YEAR))) / Constants.RAY;
    }

    function _updateInterestRateModel(address _interestRateModel) internal {
        require(
            _interestRateModel != address(0),
            "ZERO_ADDRESS_IS_NOT_ALLOWED"
        );
        interestRateModel = IInterestRateModel(_interestRateModel);
        _updateBorrowRate(0);
        emit NewInterestRateModel(_interestRateModel);
    }

    // get fix interest rate from interest model
    function _updateBorrowRate(uint256 loss) internal {
        // Update total _expectedLiquidityLU
        _expectedLiquidityLU = expectedLiquidity() - loss;
        // update borrow APY, constant RAY is 1e27, so 5% = 5 * 1e25
        borrowAPY_RAY = interestRateModel.calcBorrowRate();
        _timestampLU = block.timestamp;
    }
}
