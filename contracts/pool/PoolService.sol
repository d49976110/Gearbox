// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../core/AddressProvider.sol";
import "../tokens/DieselToken.sol";
import "../interfaces/IInterestRateModel.sol";
import "../libraries/helpers/Constants.sol";

contract PoolService is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public underlyingToken;
    address public dieselToken;

    // todo : why need this ?
    uint256 public expectedLiquidityLimit;

    // last update liquidity
    uint256 public _expectedLiquidityLU;

    uint256 public _timestampLU;

    uint256 public totalBorrowed;
    uint256 public borrowAPY_RAY;

    address public treasuryAddress;
    AddressProvider public addressProvider;
    IInterestRateModel public interestRateModel;

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

    constructor(
        address _addressProvider,
        address _underlyingToken,
        address _dieselAddress,
        address _interestRateModelAddress,
        uint256 _expectedLiquidityLimit
    ) {
        require(
            _addressProvider != address(0) &&
                _underlyingToken != address(0) &&
                _dieselAddress != address(0) &&
                _interestRateModelAddress != address(0),
            "ZERO_ADDRESS_IS_NOT_ALLOWED"
        );

        addressProvider = AddressProvider(_addressProvider);

        underlyingToken = _underlyingToken;
        dieselToken = _dieselAddress;
        treasuryAddress = addressProvider.getTreasuryContract();

        _updateInterestRateModel(_interestRateModelAddress);
        expectedLiquidityLimit = _expectedLiquidityLimit;
    }

    function addLiquidity(
        uint256 amount,
        address onBehalfOf,
        uint256 referralCode
    ) external whenNotPaused nonReentrant {
        require(onBehalfOf != address(0), "ZERO_ADDRESS_IS_NOT_ALLOWED");

        require(
            expectedLiquidity() + amount <= expectedLiquidityLimit,
            "POOL_MORE_THAN_EXPECTED_LIQUIDITY_LIMIT"
        );

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

        DieselToken(dieselToken).mint(onBehalfOf, amount);

        _expectedLiquidityLU = _expectedLiquidityLU + amount;
        _updateBorrowRate(0);

        emit AddLiquidity(msg.sender, onBehalfOf, amount, referralCode);
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

    function _updateInterestRateModel(address _interestRateModel) internal {
        require(
            _interestRateModel != address(0),
            "ZERO_ADDRESS_IS_NOT_ALLOWED"
        );
        interestRateModel = IInterestRateModel(_interestRateModel); // T:[PS-25]
        _updateBorrowRate(0); // T:[PS-26]
        emit NewInterestRateModel(_interestRateModel); // T:[PS-25]
    }

    // get fix interest rate from interest model
    function _updateBorrowRate(uint256 loss) internal {
        // Update total _expectedLiquidityLU
        _expectedLiquidityLU = expectedLiquidity() - loss;

        // update borrow APY
        borrowAPY_RAY = interestRateModel.calcBorrowRate();
        _timestampLU = block.timestamp;
    }
}
