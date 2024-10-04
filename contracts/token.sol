// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";

contract AleatoryLottery is VRFConsumerBase {
    using SafeERC20 for IERC20;

    IERC20 public aleaToken;
    bytes32 public keyHash;
    uint256 public constant STAKING_DURATION = 30 days; // Duración del staking
    uint256 public constant STAKING_REWARD = 10000; // Recompensa de staking por semana
    uint256 public constant TICKET_PRICE = 1000; // Precio de un ticket en $ALEA
    uint256 public constant MAX_TICKETS = 100000; // Número máximo de tickets
    uint256 public constant fee = 10000; // Número máximo de tickets
    address[] public participantes;

    mapping(address => uint256) public stakedBalances;
    mapping(address => uint256) public lastStakeTimestamp;
    mapping(address => uint256) public ticketCounts;

    bytes32 public requestId;
    uint256 public randomResult;

    address public poolAddress;

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event LotteryWon(address indexed user, uint256 amount);

    constructor(address _aleaToken, address _vrfCoordinator, address _linkToken, bytes32 _keyHash, address _poolAddress)
        VRFConsumerBase(_vrfCoordinator, _linkToken)
    {
        aleaToken = IERC20(_aleaToken);
        keyHash = _keyHash;
        poolAddress = _poolAddress;
    }

    function stake(uint256 _amount) external {
        require(_amount > 0, "Amount must be greater than 0");
        require(aleaToken.balanceOf(msg.sender) >= _amount, "Insufficient balance");
        
        aleaToken.safeTransferFrom(msg.sender, poolAddress, (_amount * 150) / 10000 );
        aleaToken.safeTransferFrom(msg.sender, address(this), _amount - ((_amount * 150) / 10000));

        stakedBalances[msg.sender] += _amount;
        lastStakeTimestamp[msg.sender] = block.timestamp;

        emit Staked(msg.sender, _amount);
    }

    function unstake(uint256 _amount) external {
        require(_amount > 0 && _amount <= stakedBalances[msg.sender], "Invalid amount");

       // uint256 reward = calculateReward(msg.sender);

        stakedBalances[msg.sender] -= _amount;
        lastStakeTimestamp[msg.sender] = 0;

      //  aleaToken.safeTransfer(msg.sender, _amount + reward);

        emit Unstaked(msg.sender, _amount);
    }

    function calculateReward(address _user) internal view returns (uint256) {
        uint256 elapsedTime = block.timestamp - lastStakeTimestamp[_user];
        uint256 weeks2 = elapsedTime / 1 weeks;
        return weeks2 * STAKING_REWARD * stakedBalances[_user] / 1e18;
    }

    function buyTicket(uint256 _ticketCount) external {
        require(_ticketCount > 0 && _ticketCount <= MAX_TICKETS, "Invalid ticket count");
        require(aleaToken.balanceOf(msg.sender) >= TICKET_PRICE * _ticketCount, "Insufficient balance");
        aleaToken.safeTransferFrom(msg.sender, poolAddress, (TICKET_PRICE * _ticketCount * 150) / 10000 );
        aleaToken.safeTransferFrom(msg.sender, address(this), TICKET_PRICE * _ticketCount - ((TICKET_PRICE * _ticketCount * 150) / 10000));
        ticketCounts[msg.sender] += _ticketCount;
    }

   // function withdrawRewards() external {
     //   uint256 reward = calculateReward(msg.sender);
     //   require(reward > 0, "No rewards to withdraw");

     //   aleaToken.safeTransfer(msg.sender, reward);
    //}

    function requestRandomNumber() external {
        require(LINK.balanceOf(address(this)) >= fee, "Not enough LINK tokens");
        requestId = requestRandomness(keyHash, fee);
    }

    function fulfillRandomness(bytes32 _requestId, uint256 _randomness) internal override {
        if (_requestId == requestId) {
            randomResult = _randomness;
            address winner = generateWinner();
            uint256 reward = calculateReward(winner);

            aleaToken.safeTransfer(winner, (reward * 150) / 10000 );
            aleaToken.safeTransfer(winner, reward - (reward * 150) / 10000);

            emit LotteryWon(winner, reward);
        }
    }



    function generateWinner() internal view returns (address) {
        uint256 winningTicket = randomResult % MAX_TICKETS;
        uint256 accumulatedTickets = 0;

        // Itera sobre los participantes y determina quién tiene el ticket ganador
        for (uint256 i = 0; i < participantes.length; i++) {
            uint256 userTickets = ticketCounts[participantes[i]];
            accumulatedTickets += userTickets;
            if (accumulatedTickets >= winningTicket) {
                return participantes[i]; // El participante actual es el ganador
            }
        }

        // En caso de que ocurra algún error, devuelve la dirección del contrato
        // como un "fallback" en lugar de dejar el contrato en un estado de "revert"
        return address(this);
    }
}
