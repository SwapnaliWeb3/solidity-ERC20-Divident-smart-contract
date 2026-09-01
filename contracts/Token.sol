// SPDX-License-Identifier: MIT
pragma solidity 0.7.0;

import "./IERC20.sol";
import "./IMintableToken.sol";
import "./IDividends.sol";
import "./SafeMath.sol";

contract Token is IERC20, IMintableToken, IDividends {
    // ------------------------------------------ //
    // ----- BEGIN: DO NOT EDIT THIS SECTION ---- //
    // ------------------------------------------ //
    using SafeMath for uint256;
    uint256 public totalSupply;
    uint256 public decimals = 18;
    string public name = "Test token";
    string public symbol = "TEST";
    mapping(address => uint256) public balanceOf;
    // ------------------------------------------ //
    // ----- END: DO NOT EDIT THIS SECTION ------ //
    // ------------------------------------------ //

    // ERC-20 spending allowances: token owner => token spender => token amount.
    mapping(address => mapping(address => uint256)) private allowances;

    // Earned dividends remain with the address even after transferring or burning tokens.
    mapping(address => uint256) private dividendBalance;

    // Stores all addresses that currently have tokens.
    // holderIndex stores each address's position in the list; 0 means they are not a holder.
    address[] private holders;
    mapping(address => uint256) private holderIndex;

    // IERC20

    function allowance(
        address owner,
        address spender
    ) external view override returns (uint256) {
        return allowances[owner][spender];
    }

    function approve(
        address spender,
        uint256 value
    ) external override returns (bool) {
        allowances[msg.sender][spender] = value;
        return true;
    }

    function transfer(
        address to,
        uint256 value
    ) external override returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external override returns (bool) {
        allowances[from][msg.sender] = allowances[from][msg.sender].sub(
            value,
            "Token: allowance exceeded"
        );
        _transfer(from, to, value);
        return true;
    }

    // IMintableToken

    function mint() external payable override {
        require(msg.value > 0, "Token: no ETH sent");

        balanceOf[msg.sender] = balanceOf[msg.sender].add(msg.value);
        totalSupply = totalSupply.add(msg.value);

        _addHolder(msg.sender);
    }

    function burn(address payable dest) external override {
        uint256 amount = balanceOf[msg.sender];

        // Update balance before sending ETH.
        // Keep earned dividends unchanged.
        balanceOf[msg.sender] = 0;
        totalSupply = totalSupply.sub(amount);
        _removeHolder(msg.sender);

        _sendEth(dest, amount);
    }

    // IDividends

    function getNumTokenHolders() external view override returns (uint256) {
        return holders.length;
    }

    function getTokenHolder(
        uint256 index
    ) external view override returns (address) {
        if (index == 0 || index > holders.length) {
            return address(0);
        }

        return holders[index - 1];
    }

    function recordDividend() external payable override {
        require(msg.value > 0, "Token: no ETH sent");

        uint256 supply = totalSupply;
        require(supply > 0, "Token: no tokens in circulation");

        // Calculate each holder's share.
        // Any leftover ETH stays in the contract.
        uint256 numHolders = holders.length;
        for (uint256 i = 0; i < numHolders; i += 1) {
            address holder = holders[i];

            // Holder share = dividend × holder tokens ÷ total supply.
            uint256 share = msg.value.mul(balanceOf[holder]).div(supply);

            if (share > 0) {
                dividendBalance[holder] = dividendBalance[holder].add(share);
            }
        }
    }

    // Returns the earned dividend for the address.
    function getWithdrawableDividend(
        address payee
    ) external view override returns (uint256) {
        return dividendBalance[payee];
    }

    // Reset dividend first, then send ETH.
    function withdrawDividend(address payable dest) external override {
        uint256 amount = dividendBalance[msg.sender];

        dividendBalance[msg.sender] = 0;

        _sendEth(dest, amount);
    }

    // Internal

    /**
     * Move tokens and bring both parties' holder-list membership up to date.
     */
    function _transfer(address from, address to, uint256 value) private {
        require(to != address(0), "Token: transfer to null address"); // The receiver cannot be the zero address.

        balanceOf[from] = balanceOf[from].sub(
            value,
            "Token: insufficient balance"
        ); // Subtract the transferred amount from the sender's balance.

        balanceOf[to] = balanceOf[to].add(value); //Add those tokens to the receiver's balance

        // Update holders based on their current balance.
        // A zero balance is not added as a holder.
        _syncHolder(from);
        _syncHolder(to);
    }

    function _syncHolder(address account) private {
        if (balanceOf[account] > 0) {
            _addHolder(account);
        } else {
            _removeHolder(account);
        }
    }

    function _addHolder(address account) private {
        if (holderIndex[account] == 0) {
            holders.push(account);
            holderIndex[account] = holders.length;
        }
    }

    // Remove holder using swap-and-pop.
    function _removeHolder(address account) private {
        uint256 index = holderIndex[account];

        if (index == 0) {
            return;
        }

        uint256 lastIndex = holders.length;

        if (index != lastIndex) {
            address lastHolder = holders[lastIndex - 1];
            holders[index - 1] = lastHolder;
            holderIndex[lastHolder] = index;
        }

        holders.pop();
        delete holderIndex[account];
    }

    // Helper function that actually sends ETH to an address.
    function _sendEth(address payable dest, uint256 amount) private {
        if (amount == 0) {
            return;
        }

        (bool success, ) = dest.call{value: amount}("");
        require(success, "Token: ETH transfer failed");
    }
}