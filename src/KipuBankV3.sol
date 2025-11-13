// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title KipuBankV3
 * @author Joseph Poveda
 */

/*//////////////////////////////////////////////////////////////
                        OWNABLE IMPLEMENTATION
//////////////////////////////////////////////////////////////*/

abstract contract Ownable {
    address private _owner;
    
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    
    error OwnableUnauthorizedAccount(address account);
    error OwnableInvalidOwner(address owner);
    
    constructor(address initialOwner) {
        if (initialOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(initialOwner);
    }
    
    modifier onlyOwner() {
        _checkOwner();
        _;
    }
    
    function owner() public view returns (address) {
        return _owner;
    }
    
    function _checkOwner() internal view {
        if (owner() != msg.sender) {
            revert OwnableUnauthorizedAccount(msg.sender);
        }
    }
    
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }
    
    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(newOwner);
    }
    
    function _transferOwnership(address newOwner) internal {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

/*//////////////////////////////////////////////////////////////
                        ERC20 & SAFEERC20
//////////////////////////////////////////////////////////////*/

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

library SafeERC20 {
    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeCall(token.transfer, (to, value)));
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeCall(token.transferFrom, (from, to, value)));
    }

    function safeApprove(IERC20 token, address spender, uint256 value) internal {
        bytes memory approvalCall = abi.encodeCall(token.approve, (spender, value));
        if (!_callOptionalReturnBool(token, approvalCall)) {
            _callOptionalReturn(token, abi.encodeCall(token.approve, (spender, 0)));
            _callOptionalReturn(token, approvalCall);
        }
    }

    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        bytes memory returndata = _callOptionalReturnBytes(token, data);
        if (returndata.length != 0 && !abi.decode(returndata, (bool))) {
            revert();
        }
    }

    function _callOptionalReturnBool(IERC20 token, bytes memory data) private returns (bool) {
        bytes memory returndata = _callOptionalReturnBytes(token, data);
        if (returndata.length == 0) {
            return address(token).code.length > 0;
        } else {
            return abi.decode(returndata, (bool));
        }
    }

    function _callOptionalReturnBytes(IERC20 token, bytes memory data) private returns (bytes memory) {
        (bool success, bytes memory returndata) = address(token).call(data);
        if (success) {
            return returndata;
        } else {
            if (returndata.length > 0) {
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert();
            }
        }
    }
}

/*//////////////////////////////////////////////////////////////
                    CHAINLINK PRICE FEEDS
//////////////////////////////////////////////////////////////*/

interface AggregatorV3Interface {
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
}

/*//////////////////////////////////////////////////////////////
                    UNISWAP V2 INTERFACES
//////////////////////////////////////////////////////////////*/

interface IUniswapV2Router02 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function getReserves() external view returns (
        uint112 reserve0,
        uint112 reserve1,
        uint32 blockTimestampLast
    );
}

/*//////////////////////////////////////////////////////////////
                        MAIN CONTRACT
//////////////////////////////////////////////////////////////*/

contract KipuBankV3 is Ownable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                        TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Token configuration struct - packed for gas optimization
    struct TokenInfo {
        bool isSupported;
        uint8 decimals;
        address priceFeed;
    }

    /*//////////////////////////////////////////////////////////////
                        STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Current total USDC balance in bank (6 decimals)
    uint256 public currentUSDCBalance;
    
    /// @notice Current total ETH balance in bank (18 decimals) 
    uint256 public currentETHBalance;
    
    /// @notice Current capacity in USDC (6 decimals)
    uint256 public currentCapUSDC;
    
    /// @notice Emergency pause state
    bool public isPaused;

    /*//////////////////////////////////////////////////////////////
                    CONSTANTS & IMMUTABLES
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Maximum bank capacity - 100,000 USDC (6 decimals)
    uint256 private constant MAX_CAP = 100000000000; // 100,000 USDC with 6 decimals
    
    /// @notice Wei to Gwei conversion factor
    uint256 private constant WEI_TO_GWEI = 1000000000;
    
    /// @notice ETH price feed address (immutable)
    address public immutable ethPriceFeed;
    
    /// @notice USDC token address (immutable) 
    address public immutable usdcAddress;
    
    /// @notice USDC price feed address (immutable)
    address public immutable usdcPriceFeed;
    
    /// @notice Uniswap V2 Router address (immutable)
    address public immutable uniswapRouter;
    
    /// @notice Uniswap V2 Factory address (immutable)
    address public immutable uniswapFactory;

    /*//////////////////////////////////////////////////////////////
                            MAPPINGS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice User balances in USDC (6 decimals)
    mapping(address => uint256) public userDepositUSDC;
    
    /// @notice Supported token configurations
    mapping(address => TokenInfo) public supportedTokens;

    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Emitted when user makes a deposit
    /// @param user User address
    /// @param usdcAmount USDC equivalent amount
    /// @param tokenAmount Original token amount
    /// @param timestamp Block timestamp
    event Deposit(
        address indexed user, 
        uint256 usdcAmount, 
        uint256 tokenAmount, 
        uint256 timestamp
    );
    
    /// @notice Emitted when user makes a withdrawal
    /// @param user User address
    /// @param amount Withdrawn amount
    /// @param timestamp Block timestamp
    event Withdrawal(
        address indexed user, 
        uint256 amount, 
        uint256 timestamp
    );
    
    /// @notice Emitted when token is swapped via Uniswap
    /// @param user User address
    /// @param token Input token address
    /// @param amountIn Input token amount
    /// @param amountOut Output USDC amount
    event TokenSwapped(
        address indexed user, 
        address indexed token, 
        uint256 amountIn, 
        uint256 amountOut
    );
    
    /// @notice Emitted when new token support is added
    /// @param token Token address
    /// @param decimals Token decimals
    /// @param priceFeed Price feed address
    event TokenAdded(
        address indexed token, 
        uint8 decimals, 
        address priceFeed
    );
    
    /// @notice Emitted when token support is removed
    /// @param token Token address
    event TokenRemoved(address indexed token);
    
    /// @notice Emitted when pause state changes
    /// @param isPaused New pause state
    event PauseStateChanged(bool isPaused);

    /*//////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/
    
    error ZeroAmount();
    error ZeroAddress();  
    error NotSupported();
    error CapExceeded();
    error LimitExceeded();
    error InsufficientBal();
    error TransferFailed();
    error StalePrice();
    error InvalidPrice();
    error Paused();
    error AlreadySupported();
    error NoPair();
    error SwapFailed();
    error InsufficientOut();

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Initialize KipuBankV3 with minimal gas-efficient setup
     * @param initialOwner Address of the contract owner
     * @param _ethPriceFeed ETH/USD Chainlink price feed address
     * @param _usdcAddress USDC token contract address
     * @param _usdcPriceFeed USDC/USD Chainlink price feed address  
     * @param _uniswapRouter Uniswap V2 Router address
     */
    constructor(
        address initialOwner,
        address _ethPriceFeed,
        address _usdcAddress,
        address _usdcPriceFeed,
        address _uniswapRouter
    ) Ownable(initialOwner) {
        if (_ethPriceFeed == address(0)) revert ZeroAddress();
        if (_usdcAddress == address(0)) revert ZeroAddress();
        if (_usdcPriceFeed == address(0)) revert ZeroAddress();
        if (_uniswapRouter == address(0)) revert ZeroAddress();

        ethPriceFeed = _ethPriceFeed;
        usdcAddress = _usdcAddress;
        usdcPriceFeed = _usdcPriceFeed;
        uniswapRouter = _uniswapRouter;
        uniswapFactory = IUniswapV2Router02(_uniswapRouter).factory();

        // Initialize state variables to 0
        currentUSDCBalance = 0;
        currentETHBalance = 0; 
        currentCapUSDC = 0;
    }

    /*//////////////////////////////////////////////////////////////
                    INITIALIZATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Initialize supported tokens after deployment (gas-efficient post-deployment setup)
     * @dev Must be called by owner after contract deployment
     */
    function initializeSupportedTokens() external onlyOwner {
        // Configure ETH support (address(0) represents native ETH)
        supportedTokens[address(0)] = TokenInfo({
            isSupported: true,
            decimals: 18,
            priceFeed: ethPriceFeed
        });

        // Configure USDC support
        supportedTokens[usdcAddress] = TokenInfo({
            isSupported: true,
            decimals: 6,
            priceFeed: usdcPriceFeed
        });

        emit TokenAdded(address(0), 18, ethPriceFeed);
        emit TokenAdded(usdcAddress, 6, usdcPriceFeed);
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Add support for a new ERC20 token
     * @param token Token contract address
     * @param priceFeed Chainlink price feed address for the token
     * @param decimals Number of decimals the token uses
     */
    function addSupportedToken(
        address token,
        address priceFeed,
        uint8 decimals
    ) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        if (priceFeed == address(0)) revert ZeroAddress();
        if (supportedTokens[token].isSupported) revert AlreadySupported();

        supportedTokens[token] = TokenInfo({
            isSupported: true,
            decimals: decimals,
            priceFeed: priceFeed
        });

        emit TokenAdded(token, decimals, priceFeed);
    }

    /**
     * @notice Remove support for an ERC20 token
     * @param token Token contract address to remove
     */
    function removeSupportedToken(address token) external onlyOwner {
        TokenInfo memory tokenInfo = supportedTokens[token];
        if (!tokenInfo.isSupported) revert NotSupported();

        delete supportedTokens[token];
        emit TokenRemoved(token);
    }

    /**
     * @notice Pause all contract operations
     */
    function pause() external onlyOwner {
        isPaused = true;
        emit PauseStateChanged(true);
    }

    /**
     * @notice Unpause all contract operations
     */
    function unpause() external onlyOwner {
        isPaused = false;
        emit PauseStateChanged(false);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Deposit native ETH to the bank
     * @dev Converts ETH to USDC equivalent using Chainlink oracle and respects bank cap
     */
    function depositETH() external payable {
        if (isPaused) revert Paused();
        if (msg.value == 0) revert ZeroAmount();

        // Cache state variables (single SLOAD pattern)
        uint256 cachedUSDCBalance = currentUSDCBalance;
        uint256 cachedETHBalance = currentETHBalance;
        uint256 cachedCapUSDC = currentCapUSDC;
        address userAddr = msg.sender;
        uint256 userBalance = userDepositUSDC[userAddr];

        // Convert ETH to USDC equivalent
        uint256 usdcEquivalent = _convertToUSDC(address(0), msg.value);
        
        // Check bank capacity constraint
        uint256 newCapUSDC = cachedCapUSDC + usdcEquivalent;
        if (newCapUSDC > MAX_CAP) revert CapExceeded();

        // Calculate new balances
        uint256 newUserBalance = userBalance + usdcEquivalent;
        uint256 newTotalUSDC = cachedUSDCBalance + usdcEquivalent;
        uint256 newETHBalance = cachedETHBalance + msg.value;

        // Update state (single SSTORE pattern)
        userDepositUSDC[userAddr] = newUserBalance;
        currentUSDCBalance = newTotalUSDC;
        currentETHBalance = newETHBalance;
        currentCapUSDC = newCapUSDC;

        emit Deposit(userAddr, usdcEquivalent, msg.value, block.timestamp);
    }

    /**
     * @notice Deposit ERC20 tokens (automatically swaps to USDC if not USDC)
     * @param token ERC20 token contract address
     * @param amount Amount of tokens to deposit
     * @dev Supports any token with USDC pair on Uniswap V2, auto-swaps to USDC
     */
    function depositERC20(
        address token,
        uint256 amount
    ) external {
        if (isPaused) revert Paused();
        if (amount == 0) revert ZeroAmount();

        // Verify token support (either explicitly supported or has Uniswap pair)
        TokenInfo memory config = supportedTokens[token];
        if (!config.isSupported && !_isTokenSupported(token)) {
            revert NotSupported();
        }

        // Cache state variables (single SLOAD pattern)
        uint256 cachedUSDCBalance = currentUSDCBalance;
        uint256 cachedCapUSDC = currentCapUSDC;
        address userAddr = msg.sender;
        uint256 userBalance = userDepositUSDC[userAddr];

        // Transfer tokens from user to contract
        IERC20(token).safeTransferFrom(userAddr, address(this), amount);

        uint256 usdcAmount;
        
        if (token == usdcAddress) {
            // Direct USDC deposit - no swap needed
            usdcAmount = amount;
        } else {
            // Auto-swap token to USDC via Uniswap V2
            usdcAmount = _swapTokenToUSDC(token, amount);
        }

        // Check bank capacity with final USDC amount
        uint256 newCapUSDC = cachedCapUSDC + usdcAmount;
        if (newCapUSDC > MAX_CAP) revert CapExceeded();

        // Calculate new balances
        uint256 newUserBalance = userBalance + usdcAmount;
        uint256 newTotalUSDC = cachedUSDCBalance + usdcAmount;

        // Update state (single SSTORE pattern)
        userDepositUSDC[userAddr] = newUserBalance;
        currentUSDCBalance = newTotalUSDC;
        currentCapUSDC = newCapUSDC;

        emit Deposit(userAddr, usdcAmount, amount, block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                        WITHDRAWAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Withdraw ETH from user's balance
     * @param usdcAmount USDC equivalent amount to withdraw
     * @dev Converts USDC amount to ETH equivalent and transfers ETH
     */
    function withdrawETH(uint256 usdcAmount) external {
        if (isPaused) revert Paused();
        if (usdcAmount == 0) revert ZeroAmount();

        // Cache state variables  
        address userAddr = msg.sender;
        uint256 userBalance = userDepositUSDC[userAddr];
        uint256 cachedETHBalance = currentETHBalance;
        uint256 cachedUSDCBalance = currentUSDCBalance;
        uint256 cachedCapUSDC = currentCapUSDC;

        // Validate balance
        if (usdcAmount > userBalance) revert InsufficientBal();

        // Convert USDC amount to ETH equivalent
        uint256 ethEquivalent = _convertFromUSDC(address(0), usdcAmount);
        
        // Validate ETH availability
        if (ethEquivalent > cachedETHBalance) revert InsufficientBal();

        // Calculate new balances
        uint256 newUserBalance = userBalance - usdcAmount;
        uint256 newETHBalance = cachedETHBalance - ethEquivalent;
        uint256 newUSDCBalance = cachedUSDCBalance - usdcAmount;
        uint256 newCapUSDC = cachedCapUSDC - usdcAmount;

        // Update state
        userDepositUSDC[userAddr] = newUserBalance;
        currentETHBalance = newETHBalance;
        currentUSDCBalance = newUSDCBalance;
        currentCapUSDC = newCapUSDC;

        emit Withdrawal(userAddr, ethEquivalent, block.timestamp);
        
        // Transfer ETH to user
        _transferETH(userAddr, ethEquivalent);
    }

    /**
     * @notice Withdraw USDC from user's balance
     * @param usdcAmount Amount of USDC to withdraw
     * @dev Direct USDC transfer to user
     */
    function withdrawUSDC(uint256 usdcAmount) external {
        if (isPaused) revert Paused();
        if (usdcAmount == 0) revert ZeroAmount();

        // Cache state variables
        address userAddr = msg.sender;
        uint256 userBalance = userDepositUSDC[userAddr];
        uint256 cachedUSDCBalance = currentUSDCBalance;
        uint256 cachedCapUSDC = currentCapUSDC;

        // Validate balance
        if (usdcAmount > userBalance) revert InsufficientBal();

        // Calculate new balances
        uint256 newUserBalance = userBalance - usdcAmount;
        uint256 newUSDCBalance = cachedUSDCBalance - usdcAmount;
        uint256 newCapUSDC = cachedCapUSDC - usdcAmount;

        // Update state
        userDepositUSDC[userAddr] = newUserBalance;
        currentUSDCBalance = newUSDCBalance;
        currentCapUSDC = newCapUSDC;

        emit Withdrawal(userAddr, usdcAmount, block.timestamp);
        
        // Transfer USDC to user
        IERC20(usdcAddress).safeTransfer(userAddr, usdcAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Get user's current USDC balance
     * @param user User address to query
     * @return User's balance in USDC (6 decimals)
     */
    function getUserBalance(address user) external view returns (uint256) {
        return userDepositUSDC[user];
    }

    /**
     * @notice Get comprehensive contract state information
     * @return currentUSDCBalance Total USDC in bank
     * @return currentETHBalance Total ETH equivalent in bank  
     * @return currentCapUSDC Current capacity used
     * @return maxCap Maximum bank capacity
     * @return weiToGwei Conversion factor
     * @return paused Current pause state
     */
    function getContractState() external view returns (
        uint256, uint256, uint256, uint256, uint256, bool
    ) {
        return (
            currentUSDCBalance,
            currentETHBalance, 
            currentCapUSDC,
            MAX_CAP,
            WEI_TO_GWEI,
            isPaused
        );
    }

    /**
     * @notice Get token configuration information
     * @param token Token address to query
     * @return isSupported Whether token is explicitly supported
     * @return decimals Token decimal places
     * @return priceFeed Chainlink price feed address
     */
    function getTokenInfo(
        address token
    ) external view returns (bool isSupported, uint8 decimals, address priceFeed) {
        TokenInfo memory info = supportedTokens[token];
        return (info.isSupported, info.decimals, info.priceFeed);
    }

    /**
     * @notice Get relative price between two tokens using Uniswap V2 reserves
     * @param tokenA First token address
     * @param tokenB Second token address  
     * @return Relative price of tokenA in terms of tokenB (18 decimals)
     * @dev Returns 0 if no valid pair exists, 1 ether for same token
     */
    function getPrice(address tokenA, address tokenB) external view returns (uint256) {
        if (tokenA == tokenB) {
            return 1 ether; // Same token = 1:1 ratio
        }

        // Check if tokenA has Uniswap pair support
        if (!_isTokenSupported(tokenA)) return 0;

        // Query Uniswap for relative pricing
        address[] memory path = new address[](2);
        path[0] = tokenA;
        path[1] = tokenB;

        try IUniswapV2Router02(uniswapRouter).getAmountsOut(
            1 ether, // 1 unit in 18 decimals
            path
        ) returns (uint256[] memory amounts) {
            return amounts[1];
        } catch {
            return 0; // No valid path found
        }
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Check if token has Uniswap V2 pair with USDC
     * @param token Token address to check
     * @return True if token can be swapped to USDC
     */
    function _isTokenSupported(address token) internal view returns (bool) {
        if (token == usdcAddress) return true;
        
        address pair = IUniswapV2Factory(uniswapFactory).getPair(token, usdcAddress);
        return pair != address(0);
    }

    /**
     * @notice Get latest price from Chainlink oracle with staleness check
     * @param priceFeed Chainlink price feed address
     * @return Latest price (8 decimals)
     */
    function _getLatestPrice(address priceFeed) internal view returns (uint256) {
        (, int256 price, , uint256 timeStamp, ) = AggregatorV3Interface(priceFeed).latestRoundData();
        if (price <= 0) revert InvalidPrice();
        if (block.timestamp - timeStamp > 3600) revert StalePrice(); // 1 hour max age
        return uint256(price);
    }

    /**
     * @notice Convert token amount to USDC equivalent using oracles
     * @param token Token address (address(0) for ETH)
     * @param amount Token amount to convert
     * @return USDC equivalent amount (6 decimals)
     */
    function _convertToUSDC(address token, uint256 amount) internal view returns (uint256) {
        if (token == address(0)) {
            // ETH to USDC conversion
            TokenInfo memory ethInfo = supportedTokens[address(0)];
            if (!ethInfo.isSupported) revert NotSupported();

            uint256 ethPrice = _getLatestPrice(ethInfo.priceFeed);
            // ETH (18 decimals) * Price (8 decimals) / 1e18 / 1e8 * 1e6 = USDC (6 decimals)
            return (amount * ethPrice) / 1e20; // 1e18 * 1e8 / 1e6 = 1e20
        }

        TokenInfo memory tokenInfo = supportedTokens[token];
        if (!tokenInfo.isSupported) revert NotSupported();

        uint256 tokenPrice = _getLatestPrice(tokenInfo.priceFeed);

        // Handle different decimal conversions to USDC (6 decimals)
        if (tokenInfo.decimals > 6) {
            uint256 divisor = 10 ** (tokenInfo.decimals - 6 + 8);
            return (amount * tokenPrice) / divisor;
        } else {
            uint256 multiplier = 10 ** (6 - tokenInfo.decimals);  
            return (amount * tokenPrice * multiplier) / 1e8;
        }
    }

    /**
     * @notice Convert USDC amount to token equivalent using oracles
     * @param token Token address (address(0) for ETH)
     * @param usdcAmount USDC amount to convert (6 decimals)
     * @return Token equivalent amount
     */
    function _convertFromUSDC(address token, uint256 usdcAmount) internal view returns (uint256) {
        if (token == address(0)) {
            // USDC to ETH conversion
            TokenInfo memory ethInfo = supportedTokens[address(0)];
            if (!ethInfo.isSupported) revert NotSupported();

            uint256 ethPrice = _getLatestPrice(ethInfo.priceFeed);
            // USDC (6 decimals) * 1e18 * 1e8 / Price (8 decimals) = ETH (18 decimals)
            return (usdcAmount * 1e20) / ethPrice; // 1e6 * 1e18 / price / 1e8 = 1e20 / price
        }

        TokenInfo memory tokenInfo = supportedTokens[token];
        if (!tokenInfo.isSupported) revert NotSupported();

        uint256 tokenPrice = _getLatestPrice(tokenInfo.priceFeed);

        // Handle different decimal conversions from USDC (6 decimals)
        if (tokenInfo.decimals > 6) {
            uint256 multiplier = 10 ** (tokenInfo.decimals - 6 + 8);
            return (usdcAmount * multiplier) / tokenPrice;
        } else {
            uint256 divisor = 10 ** (6 - tokenInfo.decimals);  
            return (usdcAmount * 1e8) / (tokenPrice * divisor);
        }
    }

    /**
     * @notice Swap ERC20 tokens to USDC using Uniswap V2
     * @param token Input token address
     * @param amount Amount of input tokens
     * @return Amount of USDC received from swap
     */
    function _swapTokenToUSDC(address token, uint256 amount) internal returns (uint256) {
        // Approve Uniswap router to spend tokens
        IERC20(token).safeApprove(uniswapRouter, amount);

        // Set up swap path: token -> USDC
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = usdcAddress;

        // Get expected output amounts
        uint256[] memory expectedAmounts = IUniswapV2Router02(uniswapRouter)
            .getAmountsOut(amount, path);

        // Calculate minimum output with 5% slippage protection  
        uint256 minAmountOut = (expectedAmounts[1] * 9500) / 10000;

        // Record USDC balance before swap
        uint256 balanceBefore = IERC20(usdcAddress).balanceOf(address(this));

        // Execute swap with deadline protection
        IUniswapV2Router02(uniswapRouter).swapExactTokensForTokens(
            amount,
            minAmountOut,
            path,
            address(this),
            block.timestamp + 300 // 5 minute deadline
        );

        // Calculate actual USDC received
        uint256 amountOut = IERC20(usdcAddress).balanceOf(address(this)) - balanceBefore;
        if (amountOut == 0) revert SwapFailed();
        if (amountOut < minAmountOut) revert InsufficientOut();

        emit TokenSwapped(msg.sender, token, amount, amountOut);
        return amountOut;
    }

    /**
     * @notice Safely transfer ETH to an address
     * @param to Recipient address
     * @param amount Amount of ETH to transfer (wei)
     */
    function _transferETH(address to, uint256 amount) internal {
        (bool success, ) = to.call{value: amount}("");
        if (!success) revert TransferFailed();
    }

    /*//////////////////////////////////////////////////////////////
                        RECEIVE FUNCTION
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Receive function for direct ETH deposits
     * @dev Automatically converts ETH to USDC equivalent and credits user balance
     */
    receive() external payable {
        if (isPaused) revert Paused();
        if (msg.value == 0) revert ZeroAmount();

        // Cache state variables
        uint256 cachedUSDCBalance = currentUSDCBalance;
        uint256 cachedETHBalance = currentETHBalance;
        uint256 cachedCapUSDC = currentCapUSDC;

        // Convert ETH to USDC equivalent
        uint256 usdcEquivalent = _convertToUSDC(address(0), msg.value);
        
        // Check bank capacity
        uint256 newCapUSDC = cachedCapUSDC + usdcEquivalent;
        if (newCapUSDC > MAX_CAP) revert CapExceeded();

        // Update balances
        uint256 newUserBalance = userDepositUSDC[msg.sender] + usdcEquivalent;
        uint256 newTotalUSDC = cachedUSDCBalance + usdcEquivalent;
        uint256 newETHBalance = cachedETHBalance + msg.value;

        userDepositUSDC[msg.sender] = newUserBalance;
        currentUSDCBalance = newTotalUSDC;
        currentETHBalance = newETHBalance;
        currentCapUSDC = newCapUSDC;

        emit Deposit(msg.sender, usdcEquivalent, msg.value, block.timestamp);
    }
}