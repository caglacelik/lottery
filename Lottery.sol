// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Lottery is VRFConsumerBaseV2, ConfirmedOwner, ReentrancyGuard {

    // Events
    event LotteryStarted(uint256 lotId);
    event PlayerJoined(uint256 lotId, address player);
    event LotteryEnded(uint256 lotId, address winner, uint256 reward);

    // Errors
    error DidNotPayCorrectEntryBalance(address receiver, uint256 value);
    error FailedSendingValue(address receiver);
    error LotteryHasNotEnded(address receiver);

    // Modifiers
    modifier checkEnded {
        require(currentState == LotteryState.Ended, "Lottery already started");
        _;
    }

    modifier checkStarted {
        require(currentState == LotteryState.Started, "Lottery not started");
        _;
    }

    modifier claim {
        require(address(this).balance > 0, "Nothing to claim");
        _;
    }

    // Chainlink's State Variables
    uint16 private numWords = 1;
    uint16 private requestConfirmations = 3;
    uint32 private callbackGasLimit = 100_000;
    uint64 subscriptionId;
    bytes32 private keyHash; 

    VRFCoordinatorV2Interface COORDINATOR;

    // Goerli
    // keyhash = 0x79d3d8832d904592c0bf9818b621522c988bb8b0c05cdc3b15aea1b6e8db0c15;
    // vrf coordinator address : 0x2Ca8E0C643bDe4C2E08ab1fA0da3401AdAD7734D

    // Lottery's State Variables
    uint256 private lotteryId;
    uint256 private reward;
    uint256 private profit;
    uint256 public fee;
    // winner's address => reward
    mapping(address => uint256) public winners;
    // lotteryId => players
    mapping(uint256 => address payable[]) players;

    enum LotteryState {
        Started,
        Pending,
        Ended
        }

    LotteryState public currentState;

    constructor(uint64 _subscriptionId, bytes32 _keyHash, address _vrfCoordinator, uint256 _fee)
        VRFConsumerBaseV2(_vrfCoordinator)
        ConfirmedOwner(msg.sender)
        ReentrancyGuard()
    {
        COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);
        subscriptionId = _subscriptionId;
        keyHash = _keyHash;
        fee = _fee;
    }

    function startLottery() external checkEnded onlyOwner {
        // delete players[lotteryId];
        currentState = LotteryState.Started;
        lotteryId += 1;

        emit LotteryStarted(lotteryId);
    }

    function joinLottery() public payable checkStarted {
        if (msg.value != fee) {
            revert DidNotPayCorrectEntryBalance(msg.sender, msg.value);
        }
        currentState = LotteryState.Pending;
        players[lotteryId].push(payable(msg.sender));
        reward += msg.value;

        emit PlayerJoined(lotteryId, msg.sender);
    }

    function requestRandomWords() external onlyOwner
    {
        COORDINATOR.requestRandomWords(
            keyHash,
            subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );
    }

    function fulfillRandomWords(uint256 /* requestId */, uint256[] memory _randomWords) internal override {
        uint256 index = _randomWords[0] % players[lotteryId].length;
        address winner = players[lotteryId][index];
        // %20 profit for coordinator
        uint256 _reward = reward;
        profit += (2 * _reward) / 10;
        _reward = 8 * _reward / 10;
        winners[winner] = _reward;
        reward = _reward;
        currentState = LotteryState.Ended;

        emit LotteryEnded(lotteryId, winner, reward); 
    }

    function claimReward() external nonReentrant claim {
        if (currentState != LotteryState.Ended) {
            revert LotteryHasNotEnded(msg.sender);
        }

        (bool sent,) =  msg.sender.call{value: winners[msg.sender]}("");

        if (!sent) { 
            revert FailedSendingValue(msg.sender); 
        }

        reward = 0;
        winners[msg.sender] = 0;
    }

    function claimProfit() external onlyOwner claim {
        if (currentState != LotteryState.Ended) {
            revert LotteryHasNotEnded(msg.sender);
        }

        (bool sent,) = msg.sender.call{value: profit}("");

        if (!sent) { 
            revert FailedSendingValue(msg.sender); 
        }

        profit = 0;
    }

    function getProfit() external view onlyOwner returns(uint256) {
        return profit;
    }

    function getBalance() external view returns(uint256) {
        return profit + reward;
    }

    receive() payable external {
        joinLottery();
    }

    fallback() payable external {
        joinLottery();
    }
}