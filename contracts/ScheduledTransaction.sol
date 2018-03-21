pragma solidity ^0.4.19;

import "./IPFS.sol";

contract ScheduledTransaction {
    bytes32 public ipfsHash;

    address owner = 0x0;
    bool initialized = false;
    
    // will switch to true when claimed
    bool claimed = false;
    address claimingNode = 0x0;

    // will switch to true when executed
    bool executed = false;

    // will switch if successful
    bool successful = false;

    // disallow receiving ether
    function() public {revert();}

    function init(bytes32 _ipfsHash, address _owner) public payable {
        ipfsHash = _ipfsHash;
        owner = _owner;
        initialized = true;
    }

    function execute(bytes _serializedTransaction)
        public returns (bool)
    {
        // bytes32 checkHash = IPFS(ipfs).generateHash(string(_serializedTransaction));
        // require(checkHash == ipfsHash);

        address recipient;
        uint256 value;
        uint256 callGas;
        uint256 gasPrice;
        uint256 executionWindowStart;
        uint256 executionWindowLength;
        uint256 bounty;
        uint256 fee;

        assembly {
            recipient := mload(add(_serializedTransaction, 32))
            value := mload(add(_serializedTransaction,64))
            callGas := mload(add(_serializedTransaction, 96))
            gasPrice := mload(add(_serializedTransaction, 128))
            executionWindowStart := mload(add(_serializedTransaction, 160))
            executionWindowLength := mload(add(_serializedTransaction, 192))
            bounty := mload(add(_serializedTransaction, 224))
            fee := mload(add(_serializedTransaction, 256))
            // CallData = everything after this
        }

        bytes32 callData = "";

        //check gasleft() >= requiredGas
        require(msg.gas >= callGas + 180000 - 25000);
        //check that this hasn't been executed yet
        require(!executed);
        //check in execution window
        require(block.number >= executionWindowStart && block.number < executionWindowStart + executionWindowLength);
        //if claimed, check that claimer is executed
        if (claimed && block.number < executionWindowStart + executionWindowLength / 2) {
            require(msg.sender == claimingNode);
        }
        //check gasPrice
        require(tx.gasprice == gasPrice);

        //mark that this has been executed
        executed = true;

        successful = recipient.call.value(value).gas(callGas)(callData);

        //check fee recipient, send fee
        // if (feeRecipient()) {

        // }
        //check bounty recipient, send bounty
        address bountyRecipient = msg.sender;
        bountyRecipient.transfer(bounty);
        //send remaining ether back to scheduler

        return true;
    }

    function cancel()
        public returns (bool)
    {
        // check if msg.sender == owner
        require(msg.sender == owner);
        return true;
    }

    function claim()
        public returns (bool)
    {
        return true;
    }

    function proxy(address _to, bytes _data)
        public payable returns (bool)
    {
        // require(msg.sender == owner);
        // require(isAfterWindow)
        return _to.call.value(msg.value)(_data);
    }

    // pull transactions?
}