// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// Chainlink AggregatorV3Interface
interface AggregatorV3Interface {
  function decimals() external view returns (uint8);
  function description() external view returns (string memory);
  function version() external view returns (uint256);
  function getRoundData(uint80 _roundId) external view returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    );
  function latestRoundData() external view returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    );
}

/**
 * @title KipuBankV2
 * @dev A secure bank contract that allows users to deposit and withdraw ETH and ERC20 tokens
 * with transaction limits and total deposit caps.
 */
contract KipuBankV2 is Ownable {
    using SafeERC20 for IERC20;

    // Chainlink Price Feed for ETH/USD on Sepolia
    address private constant ETH_USD_PRICE_FEED = 0x694AA1769357215DE4FAC081bf1f309aDC325306; // Sepolia ETH/USD
    
    // Maximum amount that can be withdrawn in a single transaction (in USD with 8 decimals)
    uint256 public immutable WITHDRAWAL_LIMIT_USD;
    
    // Maximum total deposits allowed in the bank (in USD with 8 decimals)
    uint256 public immutable BANK_CAP_USD;
    
    // Total deposits across all tokens (in wei or token units)
    mapping(address => uint256) public totalDeposits;
    
    // User balances: tokenAddress => userAddress => balance
    mapping(address => mapping(address => uint256)) private _balances;
    
    // Track number of deposits and withdrawals
    uint256 public totalDepositCount;
    uint256 public totalWithdrawalCount;

    // Events
    event Deposited(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 usdValue
    );
    
    event Withdrawn(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 usdValue
    );
    
    event BankCapUpdated(uint256 newCap);
    event WithdrawalLimitUpdated(uint256 newLimit);

    // Custom errors
    error InsufficientBalance(uint256 available, uint256 requested);
    error WithdrawalLimitExceeded(uint256 limit, uint256 requested);
    error BankCapExceeded(uint256 cap, uint256 requested);
    error ZeroAmount();
    error TransferFailed();
    error InvalidToken();
    error InvalidAddress();

    /**
     * @dev Constructor sets the initial owner, bank cap, and withdrawal limit
     * @param initialOwner Address of the contract owner
     * @param bankCapUSD Maximum total deposits allowed in USD (8 decimals)
     * @param withdrawalLimitUSD Maximum withdrawal per transaction in USD (8 decimals)
     */
    constructor(
        address initialOwner,
        uint256 bankCapUSD,
        uint256 withdrawalLimitUSD
    ) Ownable(initialOwner) {
        require(initialOwner != address(0), "Invalid owner address");
        require(bankCapUSD > 0, "Bank cap must be greater than zero");
        
        BANK_CAP_USD = bankCapUSD;
        WITHDRAWAL_LIMIT_USD = withdrawalLimitUSD;
    }

    /**
     * @dev Deposit ETH or ERC20 tokens into the bank
     * @param tokenAddress Address of the token to deposit (address(0) for ETH)
     * @param amount Amount to deposit (in wei or token units)
     */
    function deposit(address tokenAddress, uint256 amount) external payable {
        if (amount == 0) revert ZeroAmount();
        
        uint256 usdValue = getUSDValue(tokenAddress, amount);
        uint256 newTotalDeposits = totalDeposits[tokenAddress] + amount;
        
        // Check bank cap
        if (getTotalDepositsInUSD() + usdValue > BANK_CAP_USD) {
            revert BankCapExceeded(BANK_CAP_USD, getTotalDepositsInUSD() + usdValue);
        }

        if (tokenAddress == address(0)) {
            // Handle ETH deposit
            if (msg.value != amount) revert InsufficientBalance(amount, msg.value);
        } else {
            // Handle ERC20 deposit
            IERC20 token = IERC20(tokenAddress);
            uint256 balanceBefore = token.balanceOf(address(this));
            token.safeTransferFrom(msg.sender, address(this), amount);
            uint256 balanceAfter = token.balanceOf(address(this));
            
            // Handle tokens with fees on transfer
            if (balanceAfter - balanceBefore != amount) {
                amount = balanceAfter - balanceBefore;
                usdValue = getUSDValue(tokenAddress, amount);
            }
        }

        // Update state
        _balances[tokenAddress][msg.sender] += amount;
        totalDeposits[tokenAddress] = newTotalDeposits;
        totalDepositCount++;

        emit Deposited(msg.sender, tokenAddress, amount, usdValue);
    }

    /**
     * @dev Withdraw tokens from the bank
     * @param tokenAddress Address of the token to withdraw (address(0) for ETH)
     * @param amount Amount to withdraw (in wei or token units)
     */
    function withdraw(address tokenAddress, uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        
        // Check withdrawal limit
        uint256 usdValue = getUSDValue(tokenAddress, amount);
        if (usdValue > WITHDRAWAL_LIMIT_USD) {
            revert WithdrawalLimitExceeded(WITHDRAWAL_LIMIT_USD, usdValue);
        }

        // Check user balance
        if (_balances[tokenAddress][msg.sender] < amount) {
            revert InsufficientBalance(_balances[tokenAddress][msg.sender], amount);
        }

        // Update state before external calls (checks-effects-interactions pattern)
        _balances[tokenAddress][msg.sender] -= amount;
        totalDeposits[tokenAddress] -= amount;
        totalWithdrawalCount++;

        // Transfer tokens
        if (tokenAddress == address(0)) {
            // Handle ETH withdrawal
            (bool success, ) = payable(msg.sender).call{value: amount}("");
            if (!success) revert TransferFailed();
        } else {
            // Handle ERC20 withdrawal
            IERC20(tokenAddress).safeTransfer(msg.sender, amount);
        }

        emit Withdrawn(msg.sender, tokenAddress, amount, usdValue);
    }

    /**
     * @dev Get the balance of a specific token for a user
     * @param tokenAddress Address of the token (address(0) for ETH)
     * @param user Address of the user
     * @return User's balance of the specified token
     */
    function getBalance(address tokenAddress, address user) external view returns (uint256) {
        return _balances[tokenAddress][user];
    }

    /**
     * @dev Get the total value of all deposits in USD (8 decimals)
     * @return Total value in USD
     */
    function getTotalDepositsInUSD() public view returns (uint256) {
        // This is a simplified version. In production, you would need to:
        // 1. Track all token addresses that have been deposited
        // 2. Get current price for each token from Chainlink
        // 3. Sum up all values in USD
        
        // For now, we'll return the total ETH value in USD as a placeholder
        (, int256 price, , , ) = AggregatorV3Interface(ETH_USD_PRICE_FEED).latestRoundData();
        uint256 ethValue = (totalDeposits[address(0)] * uint256(price)) / 1e18;
        
        return ethValue;
    }

    /**
     * @dev Get the USD value of an amount of tokens
     * @param tokenAddress Address of the token (address(0) for ETH)
     * @param amount Amount of tokens to get value for
     * @return Value in USD (8 decimals)
     */
    function getUSDValue(address tokenAddress, uint256 amount) public view returns (uint256) {
        if (tokenAddress == address(0)) {
            // For ETH, use Chainlink price feed
            (, int256 price, , , ) = AggregatorV3Interface(ETH_USD_PRICE_FEED).latestRoundData();
            return (amount * uint256(price)) / 1e18; // ETH has 18 decimals, price feed has 8
        } else {
            // For ERC20 tokens, we'd need a price feed for each token
            // This is a simplified version that assumes 1:1 with USD (like USDC)
            // In production, you would use Chainlink price feeds for each token
            return amount;
        }
    }

    /**
     * @dev Emergency withdraw tokens sent to the contract by mistake
     * @param tokenAddress Address of the token to recover
     */
    function recoverTokens(address tokenAddress) external onlyOwner {
        uint256 balance;
        if (tokenAddress == address(0)) {
            balance = address(this).balance;
            (bool success, ) = owner().call{value: balance}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20 token = IERC20(tokenAddress);
            balance = token.balanceOf(address(this)) - totalDeposits[tokenAddress];
            token.safeTransfer(owner(), balance);
        }
    }

    // Allow the contract to receive ETH
    receive() external payable {}
}
