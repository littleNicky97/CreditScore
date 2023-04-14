// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TestCreditScoreNFT is ERC721, Ownable, ReentrancyGuard {
    using Counters for Counters.Counter;

    string private _tokenURI;

    event CreditScoreNFTPurchased(address indexed buyer, uint256 tokenId);
    event ContractApproved(address indexed owner, address indexed contractAddress);
    event ContractRevoked(address indexed owner, address indexed contractAddress);
    event CreditScoreUpdated(uint256 tokenId, uint256 newCreditScore, address indexed updater);
    event NFTTransferred(address indexed from, address indexed to, uint256 tokenId);

    struct CreditScoreData {
        uint256 creditScore;
        address walletAddress;
        uint256 lastUpdated;
        int256 lastScoreChange;          
        address lastUpdatedByContract;
    }

    Counters.Counter private _tokenIdCounter;
    mapping(uint256 => CreditScoreData) public creditScores;
    mapping(address => mapping(address => bool)) private _approvedContracts;
    mapping(address => uint256) private _addressToTokenId;
    mapping(uint256 => bool) private _lockedNFTs;
    mapping(address => mapping(address => uint256)) private _lastUpdatedByContract;
    mapping(address => address[]) private _userApprovedContracts;

    uint256 private constant initialCreditScore = 500;
    uint256 private constant nftPrice = 0.2 ether;

    constructor() ERC721("CidtadelScoreZ", "TEST") {
        _tokenURI = "https://raw.githubusercontent.com/littleNicky97/CitadalLoansMetadata/main/CitadelLoansMetaData?token=GHSAT0AAAAAACBHUTH2R7TDKZBJWE2D5KOOZBYIHEA";
    }

    modifier notLocked(uint256 tokenId) {
        require(!_lockedNFTs[tokenId], "NFT is locked");
        _;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");

        return _tokenURI;
    }

    function setTokenURI(string calldata newTokenURI) external onlyOwner {
        _tokenURI = newTokenURI;
    }

    function lockNFT(uint256 tokenId, address sender) external {
        require(isContractApproved(ownerOf(tokenId), sender), "Contract not approved");
        _lockedNFTs[tokenId] = true;
    }

    function unlockNFT(uint256 tokenId) external {
        require(isContractApproved(ownerOf(tokenId), msg.sender), "Contract not approved");
        _lockedNFTs[tokenId] = false;
    }

    function buyCreditScoreNFT() external payable nonReentrant {
        require(msg.value == nftPrice, "Incorrect payment value");
        require(_addressToTokenId[msg.sender] == 0, "User already owns an NFT");

        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();

        CreditScoreData memory newCreditScore = CreditScoreData(initialCreditScore, msg.sender, block.timestamp, 0, address(0));
        creditScores[tokenId] = newCreditScore;
        _mint(msg.sender, tokenId);
        _addressToTokenId[msg.sender] = tokenId;

        emit CreditScoreNFTPurchased(msg.sender, tokenId); // Emit event
    }

    function approveContract(address _contract) external {
        _approvedContracts[msg.sender][_contract] = true;
        _userApprovedContracts[msg.sender].push(_contract);
        emit ContractApproved(msg.sender, _contract); // Emit event
    }

    function revokeApproval(address _contract) external notLocked(_addressToTokenId[msg.sender]) {
        _approvedContracts[msg.sender][_contract] = false;
        for (uint256 i = 0; i < _userApprovedContracts[msg.sender].length; i++) {
            if (_userApprovedContracts[msg.sender][i] == _contract) {
                _userApprovedContracts[msg.sender][i] = _userApprovedContracts[msg.sender][_userApprovedContracts[msg.sender].length - 1];
                _userApprovedContracts[msg.sender].pop();
                break;
            }
        }
        emit ContractRevoked(msg.sender, _contract);
    }
        
    function getApprovedContracts(address user) public view returns (address[] memory) {
        return _userApprovedContracts[user];
    }

    function isContractApproved(address owner, address _contract) public view returns (bool) {
        return _approvedContracts[owner][_contract];
    }

    function updateCreditScore(uint256 tokenId, int256 scoreChange) external {
        address owner = ownerOf(tokenId);
        require(isContractApproved(owner, msg.sender), "Contract not approved");
        require(scoreChange >= -10 && scoreChange <= 10, "Score change must be within -10 to 10");

        // Check if at least 1 day (86400 seconds) has passed since the last update by this contract for this user
        uint256 timeSinceLastUpdate = block.timestamp - _lastUpdatedByContract[msg.sender][owner];
        require(timeSinceLastUpdate >= 86400, "Credit score can only be updated once a day by each contract");

        CreditScoreData storage creditScoreData = creditScores[tokenId];
        int256 newScore = int256(creditScoreData.creditScore) + scoreChange;

        require(newScore >= 350 && newScore <= 900, "Invalid credit score");

        creditScoreData.creditScore = uint256(newScore);
        creditScoreData.lastUpdated = block.timestamp;
        creditScoreData.lastScoreChange = scoreChange;           
        creditScoreData.lastUpdatedByContract = msg.sender; 

        // Update the last update timestamp for this contract and user pair
        _lastUpdatedByContract[msg.sender][owner] = block.timestamp;

        emit CreditScoreUpdated(tokenId, uint256(newScore), msg.sender); // Emit event
    }

    function _transfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override {
        require(_addressToTokenId[to] == 0, "Receiver already owns an NFT");
        super._transfer(from, to, tokenId);
        _addressToTokenId[from] = 0;
        _addressToTokenId[to] = tokenId;
        creditScores[tokenId].walletAddress = to; // update wallet address for token

        emit NFTTransferred(from, to, tokenId); // Emit event

    }
    function getCreditScoreByAddress(address walletAddress) public view returns (uint256 creditScore, uint256 lastUpdated) {
        uint256 tokenId = _addressToTokenId[walletAddress];

        // Check if the token ID exists and the wallet address is the owner of the token
        require(_exists(tokenId) && ownerOf(tokenId) == walletAddress, "User does not own a CreditScoreNFT");

        CreditScoreData storage creditScoreData = creditScores[tokenId];
        return (creditScoreData.creditScore, creditScoreData.lastUpdated);
    }

    function withdraw() external onlyOwner {
        require(address(this).balance > 0, "No funds available to withdraw");
        payable(msg.sender).transfer(address(this).balance);
    }

    function getLastScoreChangeDetails(address walletAddress) public view returns (int256 lastScoreChange, address lastUpdatedByContract) {
        uint256 tokenId = _addressToTokenId[walletAddress];
        require(_exists(tokenId) && ownerOf(tokenId) == walletAddress, "User does not own a CreditScoreNFT");

        CreditScoreData storage creditScoreData = creditScores[tokenId];
        return (creditScoreData.lastScoreChange, creditScoreData.lastUpdatedByContract);
    }
}
