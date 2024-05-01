// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./SMETXVesting.sol";
/**
 * @title Crowdsale
 * @dev Crowdsale is a base contract for managing a token crowdsale,
 * allowing investors to purchase tokens with ether. This contract implements
 * such functionality in its most fundamental form and can be extended to provide additional
 * functionality and/or custom behavior.
 * The external interface represents the basic interface for purchasing tokens, and conform
 * the base architecture for crowdsales. They are *not* intended to be modified / overriden.
 * The internal interface conforms the extensible and modifiable surface of crowdsales. Override
 * the methods to add functionality. Consider using 'super' where appropiate to concatenate
 * behavior.
 */
abstract contract Crowdsale is Initializable {
    // The token being sold
    IERC20Upgradeable public rewardToken;

    using SafeERC20Upgradeable for IERC20Upgradeable;
    IERC20Upgradeable public usdtToken;

    // Address where funds are collected
    address public wallet;

    // How many token units a buyer gets per usdt
    uint256 public rate;

    uint256 public bonusPercentage;

    // Amount of usdt raised
    uint256 public usdtRaised;

    uint256 public vestingMonths;

    uint256 round;

    uint256 public initialLockInMonths;

    SMETXVesting vestingToken;
    address public vestingAddress;
    struct UserInfo {
        uint256 usdtContributed;
        uint256 smetxRecieved;
    }

    mapping(address => UserInfo) public users;

    /**
     * Event for token purchase logging
     * @param purchaser who paid for the tokens
     * @param beneficiary who got the tokens
     * @param value usdts paid for purchase
     * @param amount amount of tokens purchased
     * @param referrer referrer for the token sale
     */
    event TokenPurchase(
        address indexed purchaser,
        address indexed beneficiary,
        uint256 value,
        uint256 amount,
        address indexed referrer
    );
    event UpdateBonusPercentage(uint256 bonus, address indexed wallet);
    event ClaimBonus(uint256 bonus, address indexed wallet);

    /**
     * @param _rate Number of token units a buyer gets per usdt
     * @param _wallet Address where collected funds will be forwarded to
     * @param _token Address of the token being sold
     */
    function __Crowdsale_init_unchained(
        uint256 _rate,
        address _wallet,
        IERC20Upgradeable _token
    ) internal {
        require(_rate > 0, "Rate cant be 0");
        require(_wallet != address(0), "Address cant be zero address");

        rate = _rate;
        wallet = _wallet;
        rewardToken = _token;
    }
    

    // -----------------------------------------
    // Crowdsale external interface
    // -----------------------------------------

    /**
     * @dev fallback function ***DO NOT OVERRIDE***
     */
    receive() external payable {}

    /**
     * @dev low level token purchase ***DO NOT OVERRIDE***
     * @param _beneficiary Address performing the token purchase
     */
    function buyTokens(
        address _beneficiary,
        address referrer,
        uint256 usdtAmount
    ) internal {
        _preValidatePurchase(_beneficiary, usdtAmount);
        usdtToken.safeTransferFrom(msg.sender, address(this), usdtAmount);
        // calculate token amount to be created
        uint256 tokens = _getTokenAmount(usdtAmount);

        // update state
        usdtRaised = usdtRaised + usdtAmount;

        UserInfo storage user = users[_beneficiary];
        user.usdtContributed += usdtAmount;
        user.smetxRecieved += tokens;

        _processPurchase(vestingAddress, tokens);

        vestingToken.addTokenGrant(
            _beneficiary,
            tokens,
            initialLockInMonths,
            vestingMonths,
            1,
            round
        );
        emit TokenPurchase(
            msg.sender,
            _beneficiary,
            usdtAmount,
            tokens,
            referrer
        );
    }

    // -----------------------------------------
    // Internal interface (extensible)
    // -----------------------------------------

    /**
     * @dev Validation of an incoming purchase. Use require statements to revert state when conditions are not met. Use super to concatenate validations.
     * @param _beneficiary Address performing the token purchase
     * @param _usdtAmount Value in usdt involved in the purchase
     */
    function _preValidatePurchase(
        address _beneficiary,
        uint256 _usdtAmount
    ) internal virtual {
        require(_beneficiary != address(0), "Address cant be zero address");
        require(_usdtAmount != 0, "Amount cant be 0");
    }

    /**
     * @dev Source of tokens. Override this method to modify the way in which the crowdsale ultimately gets and sends its tokens.
     * @param _beneficiary Address performing the token purchase
     * @param _tokenAmount Number of tokens to be emitted
     */
    function _deliverTokens(
        address _beneficiary,
        uint256 _tokenAmount
    ) internal {
        rewardToken.transfer(_beneficiary, _tokenAmount);
    }

    /**
     * @dev Executed when a purchase has been validated and is ready to be executed. Not necessarily emits/sends tokens.
     * @param _beneficiary Address receiving the tokens
     * @param _tokenAmount Number of tokens to be purchased
     */
    function _processPurchase(
        address _beneficiary,
        uint256 _tokenAmount
    ) internal {
        _deliverTokens(_beneficiary, _tokenAmount);
    }

    /**
     * @dev Override to extend the way in which ether is converted to tokens.
     * @param _usdtAmount Value in usdt to be converted into tokens
     * @return Number of tokens that can be purchased with the specified _usdtAmount
     */
    function _getTokenAmount(
        uint256 _usdtAmount
    ) internal view returns (uint256) {
        uint256 tokens = _usdtAmount * rate;
        uint256 totalTokenWithBonus = tokens +
            (tokens * bonusPercentage) / 10**2;
        return totalTokenWithBonus * 10 ** 12; // here 10**12 usdt is 6 decimal while convert to SMETX need to add 12 decimal.
    }

    /**
     * @dev Change Rate.
     * @param newRate Crowdsale rate
     */
    function _changeRate(uint256 newRate) internal virtual {
        rate = newRate;
    }

    /**
     * @dev Change initialLock in months.
     * @param _initialLockInMonths initial lock before vesting
     */
    function _changeInitialLockInMonths(
        uint256 _initialLockInMonths
    ) internal virtual {
        initialLockInMonths = _initialLockInMonths;
    }

    /**
     * @dev Change vesting in months.
     * @param vestingInMonths vesting in months
     */
    function _changeVestingInMonths(uint256 vestingInMonths) internal virtual {
        vestingMonths = vestingInMonths;
    }

    /**
     * @dev Change Rate.
     * @param newBonusPercentage Crowdsale rate
     */
    function _changeBonusPercentage(
        uint256 newBonusPercentage
    ) internal virtual {
        bonusPercentage = newBonusPercentage;
    }

    /**
     * @dev Change Token.
     * @param newToken Crowdsale token
     */
    function _changeToken(IERC20Upgradeable newToken) internal virtual {
        rewardToken = newToken;
    }

    /**
     * @dev Change Token.
     * @param updateUsdtToken usdt token
     */
    function _changeUsdtToken(
        IERC20Upgradeable updateUsdtToken
    ) internal virtual {
        usdtToken = updateUsdtToken;
    }

    /**
     * @dev Change Wallet.
     * @param newWallet Crowdsale wallet
     */
    function _changeWallet(address newWallet) internal virtual {
        wallet = newWallet;
    }
}

/**
 * @title TimedCrowdsale
 * @dev Crowdsale accepting contributions only within a time frame.
 */
abstract contract TimedCrowdsale is Crowdsale {
    uint256 public openingTime;
    uint256 public closingTime;

    event TimedCrowdsaleExtended(
        uint256 prevClosingTime,
        uint256 newClosingTime
    );

    /**
     * @dev Reverts if not in crowdsale time range.
     */
    modifier onlyWhileOpen() {
        // solium-disable-next-line security/no-block-members
        require(
            block.timestamp >= openingTime && block.timestamp <= closingTime,
            "Crowdsale has not started or has been ended"
        );
        _;
    }

    /**
     * @dev __TimedCrowdsale_init_unchained, takes crowdsale opening and closing times.
     * @param _openingTime Crowdsale opening time
     * @param _closingTime Crowdsale closing time
     */
    function __TimedCrowdsale_init_unchained(
        uint256 _openingTime,
        uint256 _closingTime
    ) internal {
        // solium-disable-next-line security/no-block-members
        require(
            _openingTime >= block.timestamp,
            "OpeningTime must be greater than current timestamp"
        );
        require(
            _closingTime >= _openingTime,
            "Closing time cant be before opening time"
        );

        openingTime = _openingTime;
        closingTime = _closingTime;
    }

    /**
     * @dev Checks whether the period in which the crowdsale is open has already elapsed.
     * @return Whether crowdsale period has elapsed
     */
    function hasClosed() public view returns (bool) {
        // solium-disable-next-line security/no-block-members
        return block.timestamp > closingTime;
    }

    /**
     * @dev Extend crowdsale.
     * @param newClosingTime Crowdsale closing time
     */
    function _extendTime(uint256 newClosingTime) internal {
        require(
            newClosingTime >= openingTime,
            "Closing time cant be before opening time"
        );
        closingTime = newClosingTime;
        emit TimedCrowdsaleExtended(closingTime, newClosingTime);
    }
}

/**
 * @title FinalizableCrowdsale
 * @dev Extension of Crowdsale where an owner can do extra work
 * after finishing.
 */
abstract contract FinalizableCrowdsale is
    TimedCrowdsale,
    OwnableUpgradeable,
    PausableUpgradeable
{
    bool public isFinalized;

    event Finalized();

    /**
     * @dev Must be called after crowdsale ends, to do some extra finalization
     * work. Calls the contract's finalization function.
     */
    function finalize() public onlyOwner whenNotPaused {
        require(!isFinalized, "Already Finalized");
        require(hasClosed(), "Crowdsale is not yet closed");

        finalization();
        emit Finalized();

        isFinalized = true;
    }

    /**
     * @dev Can be overridden to add finalization logic. The overriding function
     * should call super.finalization() to ensure the chain of finalization is
     * executed entirely.
     */
    function finalization() internal virtual {}

    function _updateFinalization() internal {
        isFinalized = false;
    }
}

contract SMETXCrowdSale is
    Crowdsale,
    PausableUpgradeable,
    FinalizableCrowdsale,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    event WithdrawToken(address token, address to, uint256 amount); // Event for Withdraw token from contract

    /**
     * @dev Initialize the crowdsale contract.
     * @param rate The rate at which tokens are sold per usdt.
     * @param wallet The address where funds are collected.
     * @param _token The token to be sold.
     * @param openingTime The start time of the crowdsale.
     * @param closingTime The end time of the crowdsale.
     */
    function initialize(
        uint256 rate,
        address wallet,
        IERC20Upgradeable _token,
        IERC20Upgradeable _usdtToken,
        uint256 openingTime,
        uint256 closingTime,
        SMETXVesting vesting, // the token
        address vestingVaultAddress // vesting Contract Address
    ) public initializer {
        round = 1;
        vestingToken = vesting;
        vestingAddress = vestingVaultAddress;
        vestingMonths = 10;
        bonusPercentage = 25;
        initialLockInMonths = 3;
        usdtToken = _usdtToken;
        __TimedCrowdsale_init_unchained(openingTime, closingTime);
        __Crowdsale_init_unchained(rate, wallet, _token);
        __Pausable_init_unchained();
        __Ownable_init_unchained();
        __Context_init_unchained();
        __ReentrancyGuard_init_unchained();
    }

    /**
     * @dev Function that should revert when `msg.sender` is not authorized to upgrade the contract. Called by
     * {upgradeTo} and {upgradeToAndCall}.
     */
    function _authorizeUpgrade(address) internal virtual override onlyOwner {}

    /**
     * @dev Pause the contract, preventing token purchases and transfers.
     * See {ERC20Pausable-_pause}.
     */
    function pauseContract() external virtual onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause the contract, allowing token purchases and transfers to resume.
     * See {ERC20Pausable-_unpause}.
     */
    function unPauseContract() external virtual onlyOwner {
        _unpause();
    }

    /**
     * @dev Purchase tokens for a specified beneficiary.
     * @param _beneficiary The address of the beneficiary.
     * @param _referrer The address of the referrer.
     */
    function buyToken(
        address _beneficiary,
        address _referrer,
        uint256 usdtAmount
    ) external onlyWhileOpen whenNotPaused nonReentrant {
        buyTokens(_beneficiary, _referrer, usdtAmount);
    }

    /**
     * @dev Finalize the crowdsale by transferring any remaining tokens to the owner.
     */
    function finalization() internal virtual override {
        uint256 balance = rewardToken.balanceOf(address(this));
        require(balance > 0, "Finalization: Insufficient token balance");
        rewardToken.transfer(owner(), balance);
    }

    /**
     * @dev Extend the sale duration by updating the closing time.
     * @param newClosingTime The new closing time for the crowdsale.
     */
    function extendSale(
        uint256 newClosingTime
    ) external virtual onlyOwner whenNotPaused {
        require(!isFinalized, "Sale Finalized");
        _extendTime(newClosingTime);
        _updateFinalization();
    }

    /**
     * @dev Change the rate at which tokens are sold per usdt.
     * @param newRate The new rate to be set.
     */
    function changeRate(
        uint256 newRate
    ) external virtual onlyOwner onlyWhileOpen whenNotPaused {
        require(newRate > 0, "Rate: Amount cannot be 0");
        _changeRate(newRate);
    }

    function changeInitialLockInMonths(
        uint256 lockInMonths
    ) external virtual onlyOwner onlyWhileOpen whenNotPaused {
        require(lockInMonths > 0, "Rate: Amount cannot be 0");
        _changeInitialLockInMonths(lockInMonths);
    }

    function changeIVestingInMonths(
        uint256 vestingInMonths
    ) external virtual onlyOwner onlyWhileOpen whenNotPaused {
        require(vestingInMonths > 0, "Rate: Amount cannot be 0");
        _changeVestingInMonths(vestingInMonths);
    }

    /**
     * @dev Change the rate at which tokens are sold per usdt.
     * @param newBonusPercentage The new rate to be set.
     */
    function changeBonusPercentage(
        uint256 newBonusPercentage
    ) external virtual onlyOwner onlyWhileOpen whenNotPaused {
        require(newBonusPercentage > 0, "Rate: Amount cannot be 0");
        _changeBonusPercentage(newBonusPercentage);
    }

    /**
     * @dev Change the token being sold in the crowdsale.
     * @param newToken The new token contract address to be used.
     */
    function changeToken(
        IERC20Upgradeable newToken
    ) external virtual onlyOwner onlyWhileOpen whenNotPaused {
        require(
            address(newToken) != address(0),
            "Token: Address cant be zero address"
        );
        _changeToken(newToken);
    }

    /**
     * @dev Change the wallet address where funds are collected.
     * @param newWallet The new wallet address to be used.
     */
    function changeWallet(
        address newWallet
    ) external virtual onlyOwner onlyWhileOpen whenNotPaused {
        require(
            newWallet != address(0),
            "Wallet: Address cant be zero address"
        );
        _changeWallet(newWallet);
    }

    /**
     * @dev Change the wallet address where funds are collected.
     * @param _usdtToken The new wallet address to be used.
     */
    function changeUsdtToken(
        IERC20Upgradeable _usdtToken
    ) external virtual onlyOwner onlyWhileOpen whenNotPaused {
        _changeUsdtToken(_usdtToken);
    }

    /**
     * @dev Allows the owner to withdraw ERC-20 tokens from this contract.
     * @param _tokenContract The address of the ERC-20 token contract.
     * @param _amount The amount of tokens to withdraw.
     * @notice The '_tokenContract' address should not be the zero address.
     */
    function withdrawToken(
        address _tokenContract,
        uint256 _amount
    ) external onlyOwner nonReentrant {
        require(_tokenContract != address(0), "Address cant be zero address");
        IERC20Upgradeable tokenContract = IERC20Upgradeable(_tokenContract);
        tokenContract.transfer(msg.sender, _amount);
        emit WithdrawToken(_tokenContract, msg.sender, _amount);
    }

    /**
     * @notice Withdraw Ether from the contract by the admin
     * @param _to The address to send the withdrawn Ether to
     * @param _amount The amount of Ether to withdraw
     */
    function withdrawEther(
        address payable _to,
        uint256 _amount
    ) external onlyOwner {
        require(_to != address(0), "Invalid recipient address");
        require(_amount > 0, "Amount must be greater than 0");
        require(
            address(this).balance >= _amount,
            "Insufficient Ether balance in the contract"
        );

        // Transfer the specified amount of Ether to the recipient
        _to.transfer(_amount);
    }
}
