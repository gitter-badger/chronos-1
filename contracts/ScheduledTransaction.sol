pragma solidity ^0.4.19;

import "./ClaimingPool.sol";
import "./IPFS.sol";
import "./Scheduler.sol";

contract ScheduledTransaction {
    bytes32 public ipfsHash;
    address public scheduledFrom;

    address public owner = 0x0;

    // will switch to true when initialized (prevents re-initialization)
    bool public initialized = false;
    
    // will switch to true when claimed
    bool public claimed = false;
    address public claimingNode = 0x0;

    // will switch to true when executed
    bool public executed = false;

    // will switch to true if successful
    bool public successful = false;

    // will switch to true if cancelled
    bool public cancelled = false;

    // disallow receiving ether
    function() public {revert();}

    address public claimingPool;

    function init(
        bytes32 _ipfsHash,
        address _owner,
        address _scheduledFrom,
        address _claimingPool
    ) public payable {
        require(!initialized);
        ipfsHash = _ipfsHash;
        owner = _owner;
        scheduledFrom = _scheduledFrom;
        claimingPool = _claimingPool;
        initialized = true;
    }

    function checkHash(bytes _s)
        public constant returns (bool)
    {
        bytes32 checkHash = IPFS(Scheduler(scheduledFrom).ipfs()).generateHash(_s);
        return checkHash == ipfsHash;
    }

    function checkInExecutionWindow(
        bytes2 temporalUnit,
        uint256 executionWindowStart,
        uint256 executionWindowLength
    ) private view returns (bool) {
        if (temporalUnit == 1) {
            return (
                block.number >= executionWindowStart &&
                block.number < executionWindowStart + executionWindowLength
            );
        } else if (temporalUnit == 2) {
            return (
                block.timestamp >= executionWindowStart &&
                block.timestamp < executionWindowStart + executionWindowLength
            );
        } else { return false; }
    }

    function checkSecondHalfOfExecutionWindow(
        bytes2 temporalUnit,
        uint256 executionWindowStart,
        uint256 executionWindowLength
    ) private view returns (bool) {
        if (temporalUnit == 1) {
            return block.number >= executionWindowStart + executionWindowLength /2;
        } else if (temporalUnit == 2) {
            return block.timestamp >= executionWindowStart + executionWindowLength /2;
        } else { return false; }
    }

    function execute(bytes _serializedTransaction)
        public returns (bool)
    {
        // uint256 startGas = msg.gas;
        require(checkHash(_serializedTransaction));

        bytes2 temporalUnit;
        address recipient;
        uint256 value;
        uint256 callGas;
        uint256 gasPrice;
        uint256 executionWindowStart;
        uint256 executionWindowLength;
        uint256 bounty;
        uint256 fee;

        assembly {
            temporalUnit := mload(add(_serializedTransaction, 32))
            recipient := mload(add(_serializedTransaction, 34))
            value := mload(add(_serializedTransaction,66))
            callGas := mload(add(_serializedTransaction, 98))
            gasPrice := mload(add(_serializedTransaction, 130))
            executionWindowStart := mload(add(_serializedTransaction, 162))
            executionWindowLength := mload(add(_serializedTransaction, 194))
            bounty := mload(add(_serializedTransaction, 226))
            fee := mload(add(_serializedTransaction, 258))
        }

        bytes memory callData = getCallData(_serializedTransaction);

        // check gasleft() >= requiredGas
        require(gasleft() >= callGas + 180000 - 25000);
        // check that this hasn't been executed yet
        require(!executed);
        // check in execution window
        require(
            checkInExecutionWindow(
                temporalUnit, 
                executionWindowStart, 
                executionWindowLength
            )
        );
        // if claimed, check that claimer is executing
        if (claimed) {
            if (msg.sender != claimingNode) {
                require(
                    checkSecondHalfOfExecutionWindow(
                        temporalUnit,
                        executionWindowStart,
                        executionWindowLength
                    )
                );
            } else {
                require(msg.sender == claimingNode);
            }
        }

        // check gasPrice
        require(tx.gasprice == gasPrice);

        // mark that this has been executed
        executed = true;

        successful = recipient.call.value(value).gas(callGas)(callData);

        // check bounty recipient, send bounty
        address bountyRecipient = msg.sender;
        bountyRecipient.transfer(bounty);

        //  check fee recipient, send fee
        address feeRecipient = Scheduler(scheduledFrom).feeRecipient();
        if (feeRecipient != 0x0) {
            feeRecipient.transfer(fee);
        }
        
        // send remaining ether back to scheduler
        owner.transfer(address(this).balance); //todo more checks on this

        return true;
    }

    function getCallData(bytes _serializedTransaction)
        private view returns (bytes)
    {
        uint256 callDataLen;
        uint256 callDataLoc;
        assembly {
            callDataLen := mload(add(_serializedTransaction, 322))
            callDataLoc := add(_serializedTransaction, 354)
        }
        return toBytes(callDataLoc, callDataLen);
    }

    function toBytes(uint256 _ptr, uint256 _len) internal view returns (bytes) {
        bytes memory ret = new bytes(_len);
        uint retptr;
        assembly { retptr := add(ret, 32)  }

        memcpy(retptr, _ptr, _len);
        return ret;
    }

    function memcpy(uint256 dest, uint src, uint len) private pure {
        // Copy word-length chunks while possible
        for(; len >= 32; len -= 32) {
            assembly {
                mstore(dest, mload(src))
            }
            dest += 32;
            src += 32;
        }
 
        // Copy remaining bytes
        uint mask = 256 ** (32 - len) - 1;
        assembly {
            let srcpart := and(mload(src), not(mask))
            let destpart := and(mload(dest), mask)
            mstore(dest, or(destpart, srcpart))
        }
    }

    function cancel()
        public returns (bool)
    {
        // check if msg.sender == owner
        require(msg.sender == owner);
        require(initialized);
        require(!cancelled);
        require(!executed);
        cancelled = true;
        owner.transfer(address(this).balance);
        return true;
    }

    function claim()
        public returns (bool)
    {
        if (claimingPool == address(0x0)) { return true; }
        // Gate
        bool canClaim = ClaimingPool(claimingPool).canClaim(msg.sender);
        require(canClaim);
        claimed = true;
        claimingNode = msg.sender;
    }

    function proxy(address _to, bytes _data)
        public payable returns (bool)
    {
        require(msg.sender == owner);
        require(executed); // make sure this is the only check we need
        return _to.call.value(msg.value)(_data);
    }

    // pull transactions?
}