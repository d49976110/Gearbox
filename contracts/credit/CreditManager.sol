// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interfaces/IAccountFactory.sol";
import "../interfaces/IPoolService.sol";
import "../interfaces/ICreditFilter.sol";
import "../interfaces/ICreditAccount.sol";

import "../libraries/helpers/Constants.sol";
import "../libraries/data/Types.sol";
import "../libraries/math/PercentageMath.sol";
import "hardhat/console.sol";

contract CreditManager is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public minAmount;
    uint256 public maxAmount;
    uint256 public maxLeverageFactor;

    // if liquidate discout 0.95 = 9500, need to divide 1e4
    uint256 public liquidationDiscount;
    uint256 public feeLiquidation;
    uint256 public feeInterest;

    address public underlyingToken;
    address public poolService;
    address public defaultSwapContract;

    mapping(address => address) public creditAccounts;
    mapping(address => bool) public contractToAdapter;

    IAccountFactory internal accountFactory;
    ICreditFilter public creditFilter;

    event OpenCreditAccount(
        address indexed sender,
        address indexed onBehalfOf,
        address indexed creditAccount,
        uint256 amount,
        uint256 borrowAmount,
        uint256 referralCode
    );
    event ExecuteOrder(address indexed borrower, address indexed target);
    event CloseCreditAccount(
        address indexed owner,
        address indexed to,
        uint256 remainingFunds
    );

    event RepayCreditAccount(address indexed owner, address indexed to);

    event LiquidateCreditAccount(
        address indexed owner,
        address indexed liquidator,
        uint256 remainingFunds
    );

    modifier allowedAdaptersOnly(address targetContract) {
        require(
            contractToAdapter[targetContract],
            "CM_TARGET_CONTRACT_iS_NOT_ALLOWED"
        );
        _;
    }

    // ! need to deploy pool service, credit fliter , account factory
    ///@param _defaultSwapContract : uniswap v2 router 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
    constructor(
        uint256 _minAmount,
        uint256 _maxAmount,
        uint256 _maxLeverage,
        address _poolService,
        address _creditFilterAddress,
        address _defaultSwapContract,
        address _accountFactory
    ) {
        require(
            _poolService != address(0) &&
                _creditFilterAddress != address(0) &&
                _defaultSwapContract != address(0),
            "ZERO_ADDRESS_IS_NOT_ALLOWED"
        );
        // AddressProvider addressProvider = AddressProvider(_addressProvider);
        poolService = _poolService;
        underlyingToken = IPoolService(_poolService).underlyingToken();

        // wethAddress = addressProvider.getWethToken();
        // wethGateway = addressProvider.getWETHGateway();
        defaultSwapContract = _defaultSwapContract;
        accountFactory = IAccountFactory(_accountFactory);

        _setParams(
            _minAmount,
            _maxAmount,
            _maxLeverage,
            Constants.FEE_INTEREST,
            Constants.FEE_LIQUIDATION,
            Constants.LIQUIDATION_DISCOUNTED_SUM
        );

        creditFilter = ICreditFilter(_creditFilterAddress);
    }

    ///@dev Set what contract can be interacted with
    /// uniswap v2 router : 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
    function setContractAdapter(address _address, bool _bool)
        external
        onlyOwner
    {
        contractToAdapter[_address] = _bool;
    }

    // todo :   liquidate , repay func
    /// @dev In underlying, user should approve this contract first
    function openCreditAccount(
        uint256 amount,
        address onBehalfOf,
        uint256 leverageFactor,
        uint256 referralCode
    ) external whenNotPaused nonReentrant {
        require(
            amount >= minAmount &&
                amount <= maxAmount &&
                leverageFactor > 0 &&
                leverageFactor <= maxLeverageFactor,
            "CM_INCORRECT_PARAMS"
        );

        require(
            onBehalfOf != address(0) && !hasOpenedCreditAccount(onBehalfOf),
            "CM_ZERO_ADDRESS_OR_USER_HAVE_ALREADY_OPEN_CREDIT_ACCOUNT"
        );

        // if leverage is 4, so leverageFactor should be 400, because LEVERAGE_DECIMALS is 100
        uint256 borrowedAmount = (amount * leverageFactor) /
            Constants.LEVERAGE_DECIMALS;

        // todo : finish account factory
        // Get Reusable Credit account creditAccount
        address creditAccount = accountFactory.takeCreditAccount(
            borrowedAmount,
            IPoolService(poolService).calcLinearCumulative_RAY()
        );

        creditFilter.initEnabledTokens(creditAccount);

        // Transfer pool tokens to new credit account
        IPoolService(poolService).lendCreditAccount(
            borrowedAmount,
            creditAccount
        );

        // Transfer borrower own fund to credit account
        IERC20(underlyingToken).safeTransferFrom(
            msg.sender,
            creditAccount,
            amount
        );

        // link credit account address with borrower address
        creditAccounts[onBehalfOf] = creditAccount;

        // emit new event
        emit OpenCreditAccount(
            msg.sender,
            onBehalfOf,
            creditAccount,
            amount,
            borrowedAmount,
            referralCode
        );
    }

    function repayCreditAccount(address to)
        external
        whenNotPaused
        nonReentrant
    {
        _repayCreditAccountImpl(msg.sender, to);
    }

    function liquidateCreditAccount(
        address borrower,
        address to,
        bool force
    ) external whenNotPaused nonReentrant {
        address creditAccount = getCreditAccountOrRevert(borrower);

        // transfer asset to liquidator, so liquidator need to approve first
        (uint256 totalValue, uint256 tvw) = _transferAssetsTo(
            creditAccount,
            to,
            force
        );

        // Checks that current Hf < 1
        require(
            tvw <
                creditFilter.calcCreditAccountAccruedInterest(creditAccount) *
                    PercentageMath.PERCENTAGE_FACTOR,
            "CM_CAN_LIQUIDATE_WITH_SUCH_HEALTH_FACTOR"
        );

        // Liquidate credit account
        (, uint256 remainingFunds) = _closeCreditAccountImpl(
            creditAccount,
            Constants.OPERATION_LIQUIDATION,
            totalValue,
            borrower,
            msg.sender,
            to
        );

        emit LiquidateCreditAccount(borrower, msg.sender, remainingFunds);
    }

    /*  
        path should be like :
            struct Exchange {
                address[] path;
                uint256 amountOutMin;
            }
     */
    function closeCreditAccount(address to, DataTypes.Exchange[] calldata paths)
        external
        whenNotPaused
        nonReentrant
    {
        address creditAccount = getCreditAccountOrRevert(msg.sender);

        // Converts all assets to underlying one. _convertAllAssetsToUnderlying is virtual
        _convertAllAssetsToUnderlying(creditAccount, paths);

        // total value equals underlying assets after converting all assets
        uint256 totalValue = IERC20(underlyingToken).balanceOf(creditAccount);

        (, uint256 remainingFunds) = _closeCreditAccountImpl(
            creditAccount,
            Constants.OPERATION_CLOSURE,
            totalValue,
            msg.sender,
            address(0),
            to
        );

        emit CloseCreditAccount(msg.sender, to, remainingFunds); // T: [CM-44]
    }

    function approve(address targetContract, address token)
        external
        whenNotPaused
        nonReentrant
    {
        require(
            contractToAdapter[targetContract] == true,
            "Not Allowed Adapter"
        );
        address creditAccount = getCreditAccountOrRevert(msg.sender);

        _provideCreditAccountAllowance(creditAccount, targetContract, token);
    }

    /// @param target nedd to be adapter, like uniswap v2 router
    function executeOrder(
        address borrower,
        address target,
        bytes memory data
    )
        external
        allowedAdaptersOnly(target)
        whenNotPaused
        nonReentrant
        returns (bytes memory)
    {
        address creditAccount = getCreditAccountOrRevert(borrower);
        emit ExecuteOrder(borrower, target);
        return ICreditAccount(creditAccount).execute(target, data);
    }

    function addCollateral(
        address onBehalfOf,
        address token,
        uint256 amount
    ) external whenNotPaused nonReentrant {
        address creditAccount = getCreditAccountOrRevert(onBehalfOf);
        require(creditFilter.checkAndEnableToken(token), "Not Allow Token");
        IERC20(token).safeTransferFrom(msg.sender, creditAccount, amount);
    }

    function hasOpenedCreditAccount(address borrower)
        public
        view
        returns (bool)
    {
        return creditAccounts[borrower] != address(0);
    }

    function getCreditAccountOrRevert(address borrower)
        public
        view
        returns (address)
    {
        address result = creditAccounts[borrower];
        require(result != address(0), "CM_NO_OPEN_ACCOUNT");
        return result;
    }

    function _transferAssetsTo(
        address creditAccount,
        address to,
        bool force
    ) internal returns (uint256 totalValue, uint256 totalWeightedValue) {
        require(to != address(0), "ZERO_ADDRESS_IS_NOT_ALLOWED");

        for (uint256 i = 0; i < creditFilter.allowedTokensCount(); i++) {
            (
                address token,
                uint256 amount,
                uint256 tv,
                uint256 tvw
            ) = creditFilter.getCreditAccountTokenById(creditAccount, i);
            if (amount > 1) {
                if (
                    _safeTokenTransfer(
                        creditAccount,
                        token,
                        to,
                        amount - 1,
                        force
                    )
                ) {
                    totalValue += tv;
                    totalWeightedValue += tvw;
                }
            }
        }
    }

    function _repayCreditAccountImpl(address borrower, address to)
        internal
        returns (uint256)
    {
        address creditAccount = getCreditAccountOrRevert(borrower);
        (uint256 totalValue, ) = _transferAssetsTo(creditAccount, to, false);

        (uint256 amountToPool, ) = _closeCreditAccountImpl(
            creditAccount,
            Constants.OPERATION_REPAY,
            totalValue,
            borrower,
            borrower,
            to
        );

        emit RepayCreditAccount(borrower, to);
        return amountToPool;
    }

    /// @param totalValue the balance of underlying after convert all assets to undeyling
    function _closeCreditAccountImpl(
        address creditAccount,
        uint8 operation,
        uint256 totalValue,
        address borrower,
        address liquidator,
        address to
    ) internal returns (uint256, uint256) {
        bool isLiquidated = operation == Constants.OPERATION_LIQUIDATION;

        (
            uint256 borrowedAmount,
            uint256 amountToPool,
            uint256 remainingFunds,
            uint256 profit,
            uint256 loss
        ) = _calcClosePayments(creditAccount, totalValue, isLiquidated);

        if (operation == Constants.OPERATION_CLOSURE) {
            ICreditAccount(creditAccount).safeTransfer(
                underlyingToken,
                poolService,
                amountToPool
            );
            require(remainingFunds > 0, "CM_CANT_CLOSE_WITH_LOSS");

            // transfer remaining funds to borrower
            _safeTokenTransfer(
                creditAccount,
                underlyingToken,
                to,
                remainingFunds,
                false
            );
        }
        // LIQUIDATION
        else if (operation == Constants.OPERATION_LIQUIDATION) {
            // repay amount to pool
            IERC20(underlyingToken).safeTransferFrom(
                liquidator,
                poolService,
                amountToPool
            );

            // transfer remaining funds to borrower
            if (remainingFunds > 0) {
                IERC20(underlyingToken).safeTransferFrom(
                    liquidator,
                    borrower,
                    remainingFunds
                );
            }
        }
        // REPAY
        else {
            // repay amount to pool
            IERC20(underlyingToken).safeTransferFrom(
                msg.sender, // msg.sender in case of WETH Gateway
                poolService,
                amountToPool
            );
        }

        // Return creditAccount
        accountFactory.returnCreditAccount(creditAccount);

        // Release memory
        delete creditAccounts[borrower];

        // Transfer pool tokens to new credit account
        IPoolService(poolService).repayCreditAccount(
            borrowedAmount,
            profit,
            loss
        );

        return (amountToPool, remainingFunds);
    }

    function _convertAllAssetsToUnderlying(
        address creditAccount,
        DataTypes.Exchange[] calldata paths
    ) internal {
        // uint256 tokenMask;

        // uint256 enabledTokens = creditFilter.enabledTokens(creditAccount);

        require(
            paths.length == creditFilter.allowedTokensCount(),
            "INCORRECT_PATH_LENGTH"
        );

        for (uint256 i = 1; i < paths.length; i++) {
            // i : the rank is the same as paths
            (address tokenAddr, uint256 amount, , ) = creditFilter
                .getCreditAccountTokenById(creditAccount, i);

            if (amount > 1) {
                _provideCreditAccountAllowance(
                    creditAccount,
                    defaultSwapContract,
                    tokenAddr
                );

                address[] memory currentPath = paths[i].path;
                currentPath[0] = tokenAddr;
                currentPath[paths[i].path.length - 1] = underlyingToken;

                bytes memory data = abi.encodeWithSelector(
                    bytes4(0x38ed1739), // "swapExactTokensForTokens(uint256 amountIn ,uint256 amountOut,address[],address,uint256)",
                    amount - 1,
                    paths[i].amountOutMin,
                    currentPath,
                    creditAccount,
                    block.timestamp
                );

                ICreditAccount(creditAccount).execute(
                    defaultSwapContract,
                    data
                );
            }
        }
    }

    function _provideCreditAccountAllowance(
        address creditAccount,
        address toContract,
        address token
    ) internal {
        ICreditAccount(creditAccount).approveToken(token, toContract);
    }

    function _setParams(
        uint256 _minAmount,
        uint256 _maxAmount,
        uint256 _maxLeverageFactor,
        uint256 _feeInterest,
        uint256 _feeLiquidation,
        uint256 _liquidationDiscount
    ) internal {
        require(
            _minAmount <= _maxAmount && _maxLeverageFactor > 0,
            "CM_INCORRECT_PARAMS"
        );

        minAmount = _minAmount;
        maxAmount = _maxAmount;
        maxLeverageFactor = _maxLeverageFactor;

        feeInterest = _feeInterest;
        feeLiquidation = _feeLiquidation;
        liquidationDiscount = _liquidationDiscount;
    }

    function _calcClosePayments(
        address creditAccount,
        uint256 totalValue,
        bool isLiquidated
    )
        public
        view
        returns (
            uint256 _borrowedAmount,
            uint256 amountToPool,
            uint256 remainingFunds,
            uint256 profit,
            uint256 loss
        )
    {
        // Gets credit account parameters
        (
            uint256 borrowedAmount,
            uint256 cumulativeIndexAtCreditAccountOpen_RAY
        ) = getCreditAccountParameters(creditAccount);

        return
            _calcClosePaymentsPure(
                totalValue,
                isLiquidated,
                borrowedAmount,
                cumulativeIndexAtCreditAccountOpen_RAY,
                IPoolService(poolService).calcLinearCumulative_RAY()
            );
    }

    function _calcClosePaymentsPure(
        uint256 totalValue,
        bool isLiquidated,
        uint256 borrowedAmount,
        uint256 cumulativeIndexAtCreditAccountOpen_RAY,
        uint256 cumulativeIndexNow_RAY
    )
        public
        view
        returns (
            uint256 _borrowedAmount,
            uint256 amountToPool,
            uint256 remainingFunds,
            uint256 profit,
            uint256 loss
        )
    {
        _borrowedAmount = borrowedAmount;
        // if liquidate , liquidation * liquidationDiscount
        uint256 totalFunds = isLiquidated
            ? (totalValue * liquidationDiscount) /
                PercentageMath.PERCENTAGE_FACTOR
            : totalValue;

        uint256 borrowedAmountWithInterest;
        if (
            cumulativeIndexNow_RAY == 0 ||
            cumulativeIndexAtCreditAccountOpen_RAY == 0
        ) {
            borrowedAmountWithInterest = borrowedAmount;
        } else {
            // borrow amount + interest should return back to the pool
            borrowedAmountWithInterest =
                (borrowedAmount * cumulativeIndexNow_RAY) /
                cumulativeIndexAtCreditAccountOpen_RAY;
        }

        if (totalFunds < borrowedAmountWithInterest) {
            // take all total funds to the pool
            amountToPool = totalFunds - 1;
            loss = borrowedAmountWithInterest - amountToPool;
        } else {
            // if liquidate , add the liquidatetion fee
            amountToPool = isLiquidated
                ? (totalFunds * feeLiquidation) /
                    1000 +
                    borrowedAmountWithInterest
                : borrowedAmountWithInterest +
                    ((borrowedAmountWithInterest - borrowedAmount) *
                        feeInterest) /
                    1000;

            if (totalFunds > amountToPool) {
                remainingFunds = totalFunds - amountToPool - 1;
            } else {
                // not enough to pay the liquidatetion fee ,take all total funds to the pool
                amountToPool = totalFunds - 1;
            }

            // pool profit, the treasure account will take
            profit = amountToPool - borrowedAmountWithInterest;
        }
    }

    function _safeTokenTransfer(
        address creditAccount,
        address token,
        address to,
        uint256 amount,
        bool force
    ) internal returns (bool) {
        try
            ICreditAccount(creditAccount).safeTransfer(token, to, amount)
        {} catch {
            require(force, "CM_TRANSFER_FAILED");
            return false;
        }

        return true;
    }

    function getCreditAccountParameters(address creditAccount)
        internal
        view
        returns (uint256 borrowedAmount, uint256 cumulativeIndexAtOpen)
    {
        borrowedAmount = ICreditAccount(creditAccount).borrowedAmount();
        cumulativeIndexAtOpen = ICreditAccount(creditAccount)
            .cumulativeIndexAtOpen();
    }

    function _checkAccountTransfer(address newOwner) internal view {
        require(
            newOwner != address(0) && !hasOpenedCreditAccount(newOwner),
            "CM_ZERO_ADDRESS_OR_USER_HAVE_ALREADY_OPEN_CREDIT_ACCOUNT"
        );
    }
}
